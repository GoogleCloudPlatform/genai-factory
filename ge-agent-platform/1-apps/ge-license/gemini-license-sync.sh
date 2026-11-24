#!/bin/bash

# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# =============================================================================
# Gemini Enterprise License Sync
# Assigns licenses by edition based on Google Group membership
#
# Maps Google Groups → Gemini Enterprise editions (Frontline, Standard, Plus)
# Uses the Discovery Engine batchUpdateUserLicenses API
#
# Usage:
#   ./gemini-license-sync.sh              # Run the sync (guided setup if unconfigured)
#   ./gemini-license-sync.sh --setup      # Force the interactive setup wizard
#   ./gemini-license-sync.sh --dry-run    # Preview changes without making API calls
#
# Configuration:
#   Run --setup for a guided wizard, or copy config.json.example to config.json.
# =============================================================================

set -euo pipefail

# Force standard C/POSIX collation so sort and comm behave identically
export LC_ALL=C

# === PARSE FLAGS ===
DRY_RUN=false
SETUP=false
NO_INPUT=false
for arg in "$@"; do
	case "$arg" in
	--dry-run) DRY_RUN=true ;;
	--setup) SETUP=true ;;
	--no-input) NO_INPUT=true ;;
	--help | -h)
		echo "Usage: $0 [--setup] [--dry-run] [--no-input]"
		echo ""
		echo "  (no flags)  Sync using config.json. If it's missing and you're in a"
		echo "              terminal, the interactive setup wizard launches."
		echo "  --setup     Force the interactive setup wizard."
		echo "  --dry-run   Preview what would happen without making API calls."
		echo "  --no-input  Never prompt; fail if config.json is missing (for cron)."
		exit 0
		;;
	*)
		echo "Unknown flag: $arg"
		echo "Usage: $0 [--setup] [--dry-run] [--no-input]"
		exit 1
		;;
	esac
done

# === PATHS & DEPENDENCIES ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"

if ! command -v jq &>/dev/null; then
	echo "ERROR: jq is not installed. Please install jq."
	echo "       macOS: brew install jq"
	echo "       Linux: sudo apt install jq"
	exit 1
fi

# === LOGGING & VISUALS ===
LOG_FILE="gemini-license-sync-$(date +%Y%m%d-%H%M%S).log"

# Google brand palette (24-bit truecolor). Blue #4285F4, Red #EA4335,
# Yellow #FBBC04, Green #34A853. Terminals without truecolor ignore these.
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[1;38;2;52;168;83m"
C_RED="\033[1;38;2;234;67;53m"
C_BLUE="\033[1;38;2;66;133;244m"
C_YELLOW="\033[1;38;2;251;188;4m"
C_CYAN="\033[1;38;2;66;133;244m" # headers use Google blue

# Nothing renders escape codes when stdout is a pipe, a cron redirect or Cloud
# Logging — they just show up as literal garbage. Drop them unless we're on a
# terminal, and honour the NO_COLOR convention.
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
	C_RESET=""
	C_BOLD=""
	C_GREEN=""
	C_RED=""
	C_BLUE=""
	C_YELLOW=""
	C_CYAN=""
fi

log() {
	local level="$1"
	shift
	local color=""
	local prefix=""

	case "$level" in
	SUCCESS)
		color="$C_GREEN"
		prefix="  ✓ "
		;;
	ERROR)
		color="$C_RED"
		prefix="  ✗ "
		;;
	INFO)
		color="$C_BLUE"
		prefix="  ℹ "
		;;
	WARN)
		color="$C_YELLOW"
		prefix="  ⚠ "
		;;
	HEADER)
		color="$C_CYAN$C_BOLD"
		prefix=""
		;;
	*)
		color="$C_RESET"
		prefix="    "
		;; # Default/None
	esac

	echo -e "${color}${prefix}$*${C_RESET}"
	# Strip ANSI codes for the log file
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | sed 's/\x1b\[[0-9;]*m//g' >>"$LOG_FILE"
}

# === CONFIG (defaults; populated from config.json or the setup wizard) ===
PROJECT_ID=""
PROJECT_NUMBER=""
LOCATION="global"
ENDPOINT_LOCATION="global"
DELETE_UNASSIGNED=false
BATCH_SIZE=100
GROUP_EMAILS=()
GROUP_SUBSCRIPTIONS=()

load_config_file() {
	PROJECT_ID=$(jq -r '.project_id // ""' "$CONFIG_FILE")
	PROJECT_NUMBER=$(jq -r '.project_number // ""' "$CONFIG_FILE")
	LOCATION=$(jq -r '.location // "global"' "$CONFIG_FILE")
	ENDPOINT_LOCATION=$(jq -r '.endpoint_location // "global"' "$CONFIG_FILE")
	DELETE_UNASSIGNED=$(jq -r '.delete_unassigned // false' "$CONFIG_FILE")
	BATCH_SIZE=$(jq -r '.batch_size // 100' "$CONFIG_FILE")

	GROUP_EMAILS=()
	GROUP_SUBSCRIPTIONS=()
	while IFS="=" read -r group sub; do
		if [ -n "$group" ] && [ -n "$sub" ]; then
			GROUP_EMAILS+=("$group")
			GROUP_SUBSCRIPTIONS+=("$sub")
		fi
	done < <(jq -r '.group_mappings | to_entries | .[] | "\(.key)=\(.value)"' "$CONFIG_FILE" 2>/dev/null || echo "")
}

# === PREREQUISITE CHECKS ===

check_prereqs() {
	local ok=true

	if ! command -v gcloud &>/dev/null; then
		echo "ERROR: gcloud is not installed. Install the Google Cloud SDK:"
		echo "       https://cloud.google.com/sdk/docs/install"
		ok=false
	fi

	if ! command -v curl &>/dev/null; then
		echo "ERROR: curl is not installed."
		ok=false
	fi

	if [ "$ok" = false ]; then
		exit 1
	fi

	if ! gcloud auth print-access-token &>/dev/null 2>&1; then
		echo "ERROR: gcloud is not authenticated. Run: gcloud auth login"
		exit 1
	fi
}

validate_config() {
	local ok=true

	# Auto-discover PROJECT_ID if empty
	if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "your-project-id" ]; then
		log INFO "Project ID not provided in config.json. Attempting auto-discovery..."
		PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
		if [ -z "$PROJECT_ID" ]; then
			log ERROR "Could not auto-discover PROJECT_ID."
			log ERROR "Please set it in config.json or run: gcloud config set project YOUR_PROJECT"
			ok=false
		else
			log SUCCESS "Auto-discovered Project ID: $PROJECT_ID"
		fi
	fi

	# Auto-discover PROJECT_NUMBER if empty
	if [ -z "$PROJECT_NUMBER" ] || [ "$PROJECT_NUMBER" = "123456789012" ]; then
		if [ -n "$PROJECT_ID" ]; then
			log INFO "Project Number not provided in config.json. Attempting auto-discovery..."
			PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)" 2>/dev/null || echo "")
			if [ -z "$PROJECT_NUMBER" ]; then
				log ERROR "Could not auto-discover PROJECT_NUMBER for project $PROJECT_ID."
				log ERROR "Check your IAM permissions or set it manually in config.json."
				ok=false
			else
				log SUCCESS "Auto-discovered Project Number: $PROJECT_NUMBER"
			fi
		else
			ok=false
		fi
	fi

	if [ ${#GROUP_EMAILS[@]} -eq 0 ]; then
		log ERROR "No group-to-subscription mappings defined."
		ok=false
	fi

	# Check for placeholder subscription IDs
	for i in "${!GROUP_EMAILS[@]}"; do
		local group_email="${GROUP_EMAILS[$i]}"
		local sub_id="${GROUP_SUBSCRIPTIONS[$i]}"
		if [[ "$sub_id" == SUBSCRIPTION_ID_* ]]; then
			log WARN "Subscription ID for ${group_email} looks like a placeholder: ${sub_id}"
			log WARN "Find real IDs via: ./gemini-helpers.sh list-configs"
			ok=false
		fi
	done

	if [ "$ok" = false ]; then
		exit 1
	fi
}

# === FUNCTIONS ===

get_group_members() {
	local group_email="$1"
	gcloud identity groups memberships list \
		--group-email="${group_email}" \
		--format="value(preferredMemberKey.id)"
}

# Stand-in config id for a seat that is ASSIGNED but carries no licenseConfig —
# typically granted by hand in the console. Such a user holds a license, so the
# sync must see them: otherwise it re-assigns them on every run and can never
# revoke them. Cannot collide with a real config id.
NO_SUBSCRIPTION="no-subscription-attached"

# updateMask is a FieldMask, serialized as a comma-separated string per the v1 schema.
UPDATE_MASK="userPrincipal,licenseConfig"

_batch_update_licenses() {
	# Low-level wrapper around batchUpdateUserLicenses. Callers pass a ready-built
	# userLicenses JSON array and the deleteUnassignedUserLicenses flag.
	local user_licenses="$1"
	local delete_unassigned="$2"

	local response
	response=$(curl -s -w "\n%{http_code}" -X POST \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Type: application/json" \
		-H "X-Goog-User-Project: ${PROJECT_ID}" \
		"https://${ENDPOINT_LOCATION}-discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/userStores/default_user_store:batchUpdateUserLicenses" \
		-d "{
      \"inlineSource\": {
        \"userLicenses\": [${user_licenses}],
        \"updateMask\": \"${UPDATE_MASK}\"
      },
      \"deleteUnassignedUserLicenses\": ${delete_unassigned}
    }")

	local http_code
	http_code=$(echo "$response" | tail -n1)
	local body
	body=$(echo "$response" | sed '$d')

	if [[ "$http_code" =~ ^2 ]]; then
		log SUCCESS "Batch succeeded (HTTP ${http_code})"
		return 0
	else
		log ERROR "Batch failed (HTTP ${http_code}): ${body}"
		return 1
	fi
}

assign_licenses_batch() {
	local subscription_id="$1"
	shift
	local emails=("$@")

	local license_config="projects/${PROJECT_NUMBER}/locations/${LOCATION}/licenseConfigs/${subscription_id}"
	local user_licenses=""

	for email in "${emails[@]}"; do
		if [ -n "$email" ]; then
			user_licenses="${user_licenses}{\"userPrincipal\":\"${email}\",\"licenseConfig\":\"${license_config}\"},"
		fi
	done
	user_licenses="${user_licenses%,}"

	if [ "$DRY_RUN" = true ]; then
		log NONE "[DRY RUN] Would assign ${#emails[@]} licenses with config: ${subscription_id}"
		for email in "${emails[@]}"; do
			[ -n "$email" ] && log NONE "[DRY RUN] ASSIGN ${email} -> ${subscription_id}"
		done
		return 0
	fi

	# Assignment never deletes: every user here carries a licenseConfig. Revocation
	# of users who left the group is handled separately by the reconcile phase.
	if _batch_update_licenses "$user_licenses" "false"; then
		# Name every user the batch actually licensed, so the log says who changed.
		for email in "${emails[@]}"; do
			[ -n "$email" ] && log SUCCESS "ASSIGNED ${email} -> ${subscription_id}"
		done
		return 0
	fi
	return 1
}

unassign_licenses_batch() {
	local subscription_id="$1"
	shift
	local emails=("$@")

	local origin="was ${subscription_id}"
	if [ "$subscription_id" = "$NO_SUBSCRIPTION" ]; then
		origin="had no subscription attached"
	fi

	# Users listed with no licenseConfig are unassigned; deleteUnassignedUserLicenses
	# then hard-deletes the stale record rather than leaving it in UNASSIGNED state.
	local user_licenses=""
	for email in "${emails[@]}"; do
		if [ -n "$email" ]; then
			user_licenses="${user_licenses}{\"userPrincipal\":\"${email}\"},"
		fi
	done
	user_licenses="${user_licenses%,}"

	if [ "$DRY_RUN" = true ]; then
		log NONE "[DRY RUN] Would revoke ${#emails[@]} licenses"
		for email in "${emails[@]}"; do
			[ -n "$email" ] && log NONE "[DRY RUN] REVOKE ${email} (${origin})"
		done
		return 0
	fi

	if _batch_update_licenses "$user_licenses" "true"; then
		# Name every user the batch actually revoked, so the log says who changed.
		for email in "${emails[@]}"; do
			[ -n "$email" ] && log WARN "REVOKED ${email} (${origin})"
		done
		return 0
	fi
	return 1
}

get_all_assigned_licenses() {
	# Emits "userPrincipal<TAB>licenseConfigId" for every currently ASSIGNED license,
	# paging through the full user store. Seats with no subscription attached are
	# emitted with NO_SUBSCRIPTION as their config id.
	local url="https://${ENDPOINT_LOCATION}-discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/userStores/default_user_store/userLicenses"
	local token=""

	# The server-side filter only saves pages: the assignment state is checked
	# again below, so the result is identical without it. Endpoints disagree on
	# the field name (the v1 docs say licenseAssignmentState, the eu endpoint
	# wants license_assignment_state), so a rejected filter drops to listing
	# everything instead of failing the run.
	local filter="license_assignment_state = ASSIGNED"

	while :; do
		local resp
		resp=$(curl -s -G \
			-H "Authorization: Bearer ${ACCESS_TOKEN}" \
			-H "X-Goog-User-Project: ${PROJECT_ID}" \
			"$url" \
			--data-urlencode "pageSize=1000" \
			${filter:+--data-urlencode "filter=${filter}"} \
			${token:+--data-urlencode "pageToken=${token}"})

		if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
			local err_msg
			err_msg=$(echo "$resp" | jq -r '.error.message // "Unknown API error"')
			if [ -n "$filter" ] && [[ "$err_msg" == *[Ff]ilter* ]]; then
				log WARN "Server rejected the license filter (${err_msg}) — listing all users instead." >&2
				filter=""
				continue
			fi
			log ERROR "Failed to fetch assigned licenses: ${err_msg}" >&2
			return 1
		fi

		echo "$resp" | jq -r --arg nosub "$NO_SUBSCRIPTION" '.userLicenses[]?
      | select((.licenseAssignmentState // "") == "ASSIGNED")
      | select((.userPrincipal // "") != "")
      | [(.userPrincipal | ascii_downcase),
         (if (.licenseConfig // "") == "" then $nosub else (.licenseConfig | split("/") | last) end)]
      | @tsv'

		token=$(echo "$resp" | jq -r '.nextPageToken // ""')
		[ -z "$token" ] && break
	done
}

list_license_config_ids() {
	# Lists license config IDs. Optional args override the endpoint/path location
	# (used by the wizard to probe global/us/eu). Note: only surfaces configs that
	# already have usage stats — a brand-new subscription with zero assignments may
	# not appear until its first assignment.
	local host_loc="${1:-$ENDPOINT_LOCATION}" path_loc="${2:-$LOCATION}"
	curl -s -X GET \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Type: application/json" \
		-H "X-Goog-User-Project: ${PROJECT_ID}" \
		"https://${host_loc}-discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/${path_loc}/userStores/default_user_store/licenseConfigsUsageStats" |
		jq -r '.licenseConfigUsageStats[]? | .licenseConfig | split("/") | last'
}

# Replaces any "auto" subscription value with the project's license config.
# Only unambiguous when the project has exactly one config; otherwise it lists
# the choices and exits so the user sets an explicit ID.
resolve_subscriptions() {
	local need_resolve=false
	for i in "${!GROUP_SUBSCRIPTIONS[@]}"; do
		case "${GROUP_SUBSCRIPTIONS[$i]}" in auto | AUTO) need_resolve=true ;; esac
	done
	[ "$need_resolve" = false ] && return 0

	log INFO "Auto-resolving 'auto' subscription IDs from project ${PROJECT_ID}..."

	local config_arr=()
	while IFS= read -r c; do
		[ -n "$c" ] && config_arr+=("$c")
	done < <(list_license_config_ids)

	local count=${#config_arr[@]}
	if [ "$count" -eq 0 ]; then
		log ERROR "No license configs found in project ${PROJECT_ID}; cannot auto-resolve."
		log ERROR "Assign at least one license first, or set the subscription ID explicitly."
		exit 1
	fi

	for i in "${!GROUP_SUBSCRIPTIONS[@]}"; do
		case "${GROUP_SUBSCRIPTIONS[$i]}" in
		auto | AUTO)
			if [ "$count" -eq 1 ]; then
				GROUP_SUBSCRIPTIONS[$i]="${config_arr[0]}"
				log SUCCESS "Resolved ${GROUP_EMAILS[$i]} -> ${config_arr[0]}"
			else
				log ERROR "Multiple license configs exist — cannot auto-resolve '${GROUP_EMAILS[$i]}'."
				log ERROR "Set an explicit subscription ID in config.json. Available configs:"
				for c in "${config_arr[@]}"; do log NONE "    - $c"; done
				exit 1
			fi
			;;
		esac
	done
}

# === INTERACTIVE SETUP WIZARD ===

# Prompt for a value; returns the answer (or the default on empty/EOF).
_ask() {
	local prompt="$1" default="${2:-}" ans
	if [ -n "$default" ]; then
		read -r -p "${prompt} [${default}]: " ans || true
		echo "${ans:-$default}"
	else
		read -r -p "${prompt}: " ans || true
		echo "$ans"
	fi
}

# Yes/no prompt; returns 0 for yes, 1 for no. Second arg is the default (Y or N).
_ask_yn() {
	local prompt="$1" default="${2:-N}" ans hint="[y/N]"
	[ "$default" = "Y" ] && hint="[Y/n]"
	read -r -p "${prompt} ${hint}: " ans || true
	ans="${ans:-$default}"
	case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

_wiz_rule() { echo -e "${C_CYAN}--------------------------------------------------${C_RESET}"; }
_wiz_step() {
	echo ""
	_wiz_rule
	echo -e "${C_CYAN}${C_BOLD}Step $1/5 — $2${C_RESET}"
	echo ""
}

write_config_json() {
	local maps="{}" idx
	for idx in "${!GROUP_EMAILS[@]}"; do
		maps=$(printf '%s' "$maps" | jq \
			--arg k "${GROUP_EMAILS[$idx]}" --arg v "${GROUP_SUBSCRIPTIONS[$idx]}" \
			'. + {($k): $v}')
	done
	jq -n \
		--arg pid "$PROJECT_ID" \
		--arg pnum "$PROJECT_NUMBER" \
		--arg loc "$LOCATION" \
		--arg eloc "$ENDPOINT_LOCATION" \
		--argjson del "$DELETE_UNASSIGNED" \
		--argjson bs "$BATCH_SIZE" \
		--argjson maps "$maps" \
		'{project_id:$pid, project_number:$pnum, location:$loc, endpoint_location:$eloc, delete_unassigned:$del, batch_size:$bs, group_mappings:$maps}' \
		>"$CONFIG_FILE"
}

run_wizard() {
	clear 2>/dev/null || true
	echo -e "${C_CYAN}${C_BOLD}"
	echo "  ╔════════════════════════════════════════════════╗"
	echo "  ║     Gemini Enterprise License Sync — Setup      ║"
	echo "  ╚════════════════════════════════════════════════╝"
	echo -e "${C_RESET}"
	echo "  This wizard maps Google Groups to Gemini Enterprise license"
	echo "  editions, then assigns (and optionally revokes) licenses so the"
	echo "  group stays the source of truth. Here's what happens:"
	echo ""
	echo -e "    ${C_BLUE}1.${C_RESET} Confirm your Google Cloud project"
	echo -e "    ${C_RED}2.${C_RESET} Discover your license region & editions (subscriptions)"
	echo -e "    ${C_YELLOW}3.${C_RESET} Map each Google Group to an edition"
	echo -e "    ${C_GREEN}4.${C_RESET} Choose whether to revoke licenses when people leave a group"
	echo -e "    ${C_BLUE}5.${C_RESET} Review, optionally save config.json, then preview or run"
	echo ""
	echo "  Nothing is changed until the final step — and a dry run is offered first."
	echo ""
	_ask_yn "Ready to begin?" "Y" || {
		echo "Setup cancelled."
		exit 0
	}

	# --- Step 1: Project ---
	_wiz_step 1 "Google Cloud project"
	echo "Detecting your active project from gcloud..."
	local detected_project detected_number
	detected_project=$(gcloud config get-value project 2>/dev/null || echo "")
	if [ -n "$detected_project" ]; then
		echo -e "  ${C_GREEN}✓ Detected: ${detected_project}${C_RESET}  (press Enter to accept, or type another)"
	fi
	PROJECT_ID=$(_ask "Project ID" "$detected_project")
	[ -z "$PROJECT_ID" ] && {
		echo -e "${C_RED}A project ID is required.${C_RESET}"
		exit 1
	}
	echo "Looking up the project number..."
	detected_number=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)" 2>/dev/null || echo "")
	[ -n "$detected_number" ] && echo -e "  ${C_GREEN}✓ Detected: ${detected_number}${C_RESET}  (press Enter to accept)"
	PROJECT_NUMBER=$(_ask "Project number" "$detected_number")
	[ -z "$PROJECT_NUMBER" ] && {
		echo -e "${C_RED}A project number is required (check IAM permissions).${C_RESET}"
		exit 1
	}
	echo -e "${C_GREEN}✓ Using ${PROJECT_ID} (${PROJECT_NUMBER})${C_RESET}"

	# --- Step 2: Discover region + editions ---
	# Licenses are tied to a specific multi-region. The set is per-project (some,
	# like 'ca', are whitelisted per customer) and there is no locations.list API,
	# so we probe a common set to auto-discover and always allow manual entry.
	_wiz_step 2 "License region & editions"
	echo -e "${C_YELLOW}Licenses are tied to a specific multi-region — pick the one where your"
	echo -e "subscription was provisioned (shown in the Cloud console under Location).${C_RESET}"
	echo ""
	echo "Probing common multi-regions for subscriptions..."
	local loc_cfg idx
	loc_cfg=$(mktemp)
	local L
	for L in global us eu ca au; do
		while IFS= read -r c; do
			[ -n "$c" ] && printf '%s\t%s\n' "$L" "$c" >>"$loc_cfg"
		done < <(list_license_config_ids "$L" "$L" 2>/dev/null || true)
	done

	local locs=()
	while IFS= read -r L; do [ -n "$L" ] && locs+=("$L"); done < <(cut -f1 "$loc_cfg" | sort -u)
	local loccount=${#locs[@]}
	echo ""

	if [ "$loccount" -eq 0 ]; then
		echo -e "${C_YELLOW}⚠ No subscriptions auto-detected (checked global, us, eu, ca, au).${C_RESET}"
		echo "  A whitelisted region may not have been probed, or none are assigned yet."
		LOCATION=$(_ask "Enter your multi-region code (e.g. global, us, eu, ca)" "global")
	else
		echo -e "${C_GREEN}Subscriptions found in these regions:${C_RESET}"
		for idx in "${!locs[@]}"; do
			local n
			n=$(awk -F'\t' -v l="${locs[$idx]}" '$1 == l' "$loc_cfg" | wc -l | tr -d ' ')
			printf "   %d) %s  (%s subscription(s))\n" "$((idx + 1))" "${locs[$idx]}" "$n"
		done
		local manual_choice=$((loccount + 1))
		printf "   %d) Other — enter a region code manually\n" "$manual_choice"
		echo "A single run manages one region."
		local lc
		lc=$(_ask "Choose a region number" "1")
		if [ "$lc" = "$manual_choice" ]; then
			LOCATION=$(_ask "Enter your multi-region code (e.g. global, us, eu, ca)" "")
		elif [ "$lc" -ge 1 ] 2>/dev/null && [ "$lc" -le "$loccount" ]; then
			LOCATION="${locs[$((lc - 1))]}"
		else
			echo -e "   ${C_YELLOW}Invalid choice — using ${locs[0]}.${C_RESET}"
			LOCATION="${locs[0]}"
		fi
	fi
	[ -z "$LOCATION" ] && LOCATION="global"
	ENDPOINT_LOCATION="$LOCATION"
	echo -e "${C_GREEN}✓ Using region '${LOCATION}'.${C_RESET}"

	# Subscriptions for the chosen region — reuse the probe results, or fetch fresh
	# if the region was entered manually and wasn't in the probe set.
	local configs=()
	while IFS= read -r c; do
		[ -n "$c" ] && configs+=("$c")
	done < <(awk -F'\t' -v l="$LOCATION" '$1 == l {print $2}' "$loc_cfg")
	rm -f "$loc_cfg"
	if [ ${#configs[@]} -eq 0 ]; then
		while IFS= read -r c; do
			[ -n "$c" ] && configs+=("$c")
		done < <(list_license_config_ids "$LOCATION" "$LOCATION" 2>/dev/null || true)
	fi
	local ccount=${#configs[@]}

	if [ "$ccount" -gt 0 ]; then
		echo -e "${C_GREEN}Found ${ccount} subscription(s) in ${LOCATION}:${C_RESET}"
		for idx in "${!configs[@]}"; do printf "   %d) %s\n" "$((idx + 1))" "${configs[$idx]}"; done
	else
		echo -e "${C_YELLOW}No subscriptions found in '${LOCATION}'.${C_RESET}"
		echo "  Double-check the region (licenses are region-bound), or enter a"
		echo "  subscription ID manually when mapping below."
	fi

	# --- Step 3: Group mappings ---
	_wiz_step 3 "Map Google Groups to editions"
	echo "For each edition, name the Google Group whose members should get it."
	echo "Members of that group are assigned the license; the group is the truth."
	GROUP_EMAILS=()
	GROUP_SUBSCRIPTIONS=()
	while :; do
		echo ""
		local g
		g=$(_ask "Google Group email (blank to finish)" "")
		[ -z "$g" ] && break

		local preview
		if preview=$(get_group_members "$g" 2>/dev/null); then
			local mc
			mc=$(printf '%s\n' "$preview" | grep -c . || true)
			echo -e "   ${C_GREEN}✓ ${g}: ${mc} member(s)${C_RESET}"
		else
			echo -e "   ${C_YELLOW}⚠ Couldn't read '${g}' (permissions, or it doesn't exist).${C_RESET}"
			_ask_yn "   Add it anyway?" "N" || continue
		fi

		local sub=""
		if [ "$ccount" -eq 1 ]; then
			sub="${configs[0]}"
			echo -e "   Only one edition exists → mapping to ${C_BOLD}${sub}${C_RESET}"
		elif [ "$ccount" -gt 1 ]; then
			local choice
			choice=$(_ask "   Edition number (1-${ccount})" "1")
			if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$ccount" ]; then
				sub="${configs[$((choice - 1))]}"
			else
				echo -e "   ${C_RED}Invalid choice — skipping this group.${C_RESET}"
				continue
			fi
		else
			sub=$(_ask "   Subscription ID for this group" "")
			[ -z "$sub" ] && {
				echo "   Skipped (no subscription)."
				continue
			}
		fi

		GROUP_EMAILS+=("$g")
		GROUP_SUBSCRIPTIONS+=("$sub")
		echo -e "   ${C_GREEN}✓ ${g} → ${sub}${C_RESET}"
		_ask_yn "Add another group?" "N" || break
	done
	if [ ${#GROUP_EMAILS[@]} -eq 0 ]; then
		echo -e "${C_RED}No mappings defined — nothing to do.${C_RESET}"
		exit 1
	fi

	# --- Step 4: Revocation policy ---
	_wiz_step 4 "Revocation policy"
	echo "When someone LEAVES a group, should the script revoke their license?"
	echo ""
	echo -e "  ${C_BOLD}No${C_RESET}  (recommended to start): only assigns/updates. People who left"
	echo "       a group keep their license. Safe — nothing is ever removed."
	echo -e "  ${C_BOLD}Yes${C_RESET} (full sync): after assigning, revokes the license of anyone"
	echo "       assigned to a managed edition who is no longer in its group."
	echo -e "       ${C_YELLOW}Access is removed immediately on the next run.${C_RESET}"
	echo ""
	if _ask_yn "Revoke licenses for users who left the group?" "N"; then
		DELETE_UNASSIGNED=true
	else
		DELETE_UNASSIGNED=false
	fi
	BATCH_SIZE=100

	# --- Step 5: Review, save, run ---
	_wiz_step 5 "Review"
	echo -e "${C_BOLD}Project:${C_RESET}          ${PROJECT_ID} (${PROJECT_NUMBER})"
	echo -e "${C_BOLD}Location:${C_RESET}         ${LOCATION} / ${ENDPOINT_LOCATION}"
	echo -e "${C_BOLD}Revoke on leave:${C_RESET}  ${DELETE_UNASSIGNED}"
	echo -e "${C_BOLD}Mappings:${C_RESET}"
	for idx in "${!GROUP_EMAILS[@]}"; do
		printf "   %s → %s\n" "${GROUP_EMAILS[$idx]}" "${GROUP_SUBSCRIPTIONS[$idx]}"
	done
	echo ""
	if _ask_yn "Save this to config.json for future runs?" "Y"; then
		write_config_json
		echo -e "${C_GREEN}✓ Wrote ${CONFIG_FILE}${C_RESET}"
	fi

	echo ""
	echo "How do you want to run now?"
	echo "   1) Dry run  — preview only, no changes (recommended first)"
	echo "   2) Live run — actually assign/revoke licenses"
	echo "   3) Quit     — don't run yet"
	local rc
	rc=$(_ask "Choose 1-3" "1")
	case "$rc" in
	1) DRY_RUN=true ;;
	2)
		DRY_RUN=false
		_ask_yn "This will modify real licenses. Continue?" "N" ||
			{
				echo "Cancelled — run later with: ./gemini-license-sync.sh"
				exit 0
			}
		;;
	*)
		echo "Okay — run later with: ./gemini-license-sync.sh"
		exit 0
		;;
	esac
}

# === BOOTSTRAP (prereqs, then load config from the wizard or config.json) ===
check_prereqs
# Cache the token once and reuse it — avoids repeated gcloud calls and expiry risk.
ACCESS_TOKEN="$(gcloud auth print-access-token)"

WIZARD=false
if [ "$SETUP" = true ]; then
	WIZARD=true
elif [ ! -f "$CONFIG_FILE" ]; then
	if [ "$NO_INPUT" = true ]; then
		echo "ERROR: config.json not found and --no-input was set."
		exit 1
	elif [ -t 0 ] && [ -t 1 ]; then
		WIZARD=true
	else
		echo "ERROR: Configuration file not found at ${CONFIG_FILE}"
		echo "       Run: ./gemini-license-sync.sh --setup   (guided setup)"
		echo "       or copy config.json.example to config.json and edit it."
		exit 1
	fi
fi

if [ "$WIZARD" = true ]; then
	run_wizard
else
	load_config_file
	validate_config
fi

# === MAIN ===

echo ""
log HEADER "=========================================="
if [ "$DRY_RUN" = true ]; then
	log WARN "*** DRY RUN MODE — no changes will be made ***"
fi
log HEADER "Gemini Enterprise License Sync Starting"
log NONE "Project: ${PROJECT_ID} | Location: ${LOCATION}"
log NONE "Delete unassigned: ${DELETE_UNASSIGNED}"
log HEADER "=========================================="

resolve_subscriptions

TOTAL_ASSIGNED=0
TOTAL_REVOKED=0
TOTAL_ERRORS=0
TOTAL_MEMBERS_CHECKED=0
TOTAL_ALREADY_ASSIGNED=0
GROUP_FETCH_FAILURES=0

# Temp files for desired assignments and current license snapshot.
# DESIRED_FILE records "configId<TAB>email" for every desired assignment and
# "configId<TAB>" marker per successfully-fetched group so reconcile knows
# which editions are safe to revoke from.
DESIRED_FILE=$(mktemp)
CURRENT_LICENSES_FILE=$(mktemp)
REFRESHED_LICENSES_FILE=$(mktemp)
trap 'rm -f "$DESIRED_FILE" "$CURRENT_LICENSES_FILE" "$REFRESHED_LICENSES_FILE"' EXIT

log INFO "Fetching current license assignments..."
# Without this snapshot the script cannot tell a new user from an existing one,
# so it would re-assign everybody and revoke nobody. Fail instead of guessing.
if ! get_all_assigned_licenses >"$CURRENT_LICENSES_FILE"; then
	log ERROR "Could not fetch current license assignments — aborting rather than"
	log ERROR "re-assigning every group member against an unknown state."
	exit 1
fi

initial_assigned_count=$(awk 'NF' "$CURRENT_LICENSES_FILE" | wc -l | tr -d ' ')
log INFO "Found ${initial_assigned_count} currently assigned license(s) across project."

unattached_count=$(awk -F'\t' -v s="$NO_SUBSCRIPTION" '$2 == s' "$CURRENT_LICENSES_FILE" | wc -l | tr -d ' ')
if [ "$unattached_count" -gt 0 ]; then
	log INFO "Of those, ${unattached_count} have no subscription attached (assigned outside this script)."
fi

# Break the snapshot down by subscription. Seats outside config.json are the ones
# worth naming: they are still revoked, but on the union of all groups rather
# than on one edition's group.
managed_subscriptions=$(printf '%s\n' "${GROUP_SUBSCRIPTIONS[@]}" | awk 'NF' | LC_ALL=C sort -u)
unmanaged_note="not in config.json"
if [ "$DELETE_UNASSIGNED" = true ]; then
	unmanaged_note="not in config.json — revoked unless the holder is in a group"
fi
log NONE "  Assigned licenses by subscription:"
while read -r seat_count cfg; do
	[ -z "$cfg" ] && continue
	if [ "$cfg" = "$NO_SUBSCRIPTION" ]; then
		log NONE "    ${seat_count}  no subscription attached (${unmanaged_note})"
	elif printf '%s\n' "$managed_subscriptions" | grep -qxF -- "$cfg"; then
		log NONE "    ${seat_count}  ${cfg} (in config.json)"
	else
		log WARN "    ${seat_count}  ${cfg} (${unmanaged_note})"
	fi
done < <(awk -F'\t' 'NF {print $2}' "$CURRENT_LICENSES_FILE" | LC_ALL=C sort | uniq -c)

for i in "${!GROUP_EMAILS[@]}"; do
	group_email="${GROUP_EMAILS[$i]}"
	subscription_id="${GROUP_SUBSCRIPTIONS[$i]}"
	log HEADER ""
	log HEADER "Processing group: ${group_email}"
	log NONE "  Subscription ID: ${subscription_id}"

	# Under `set -e` a failing command substitution in a bare assignment aborts the
	# script, so branch on the fetch directly to skip just this group on error.
	if ! members_raw=$(get_group_members "$group_email"); then
		log ERROR "Failed to fetch members for $group_email. See gcloud error above."
		TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
		GROUP_FETCH_FAILURES=$((GROUP_FETCH_FAILURES + 1))
		continue
	fi

	# Normalize emails: lowercase, non-empty, unique, sorted with LC_ALL=C
	members_sorted=$(printf '%s\n' "$members_raw" | tr '[:upper:]' '[:lower:]' | awk 'NF' | LC_ALL=C sort -u)

	if [ -n "$members_sorted" ]; then
		member_count=$(printf '%s\n' "$members_sorted" | wc -l | tr -d ' ')
	else
		member_count=0
	fi

	TOTAL_MEMBERS_CHECKED=$((TOTAL_MEMBERS_CHECKED + member_count))

	# Record desired state now that the fetch succeeded (even if empty).
	printf '%s\t\n' "$subscription_id" >>"$DESIRED_FILE"
	if [ "$member_count" -gt 0 ]; then
		printf '%s\n' "$members_sorted" | awk -v s="$subscription_id" '{print s "\t" $0}' >>"$DESIRED_FILE"
	fi

	if [ "$member_count" -eq 0 ]; then
		log WARN "No members found in group — skipping assignment"
		continue
	fi

	# Extract users currently assigned to this subscription_id from snapshot, plus
	# those holding a seat with no subscription attached: they are licensed too, so
	# re-assigning them would report a change that never happened.
	current_assigned_for_sub=$(awk -F'\t' -v c="$subscription_id" -v s="$NO_SUBSCRIPTION" \
		'$2 == c || $2 == s {print tolower($1)}' "$CURRENT_LICENSES_FILE" | awk 'NF' | LC_ALL=C sort -u)

	# Calculate delta: users in group who DO NOT have this subscription
	to_assign_raw=$(comm -23 \
		<(printf '%s\n' "$members_sorted" | awk 'NF') \
		<(printf '%s\n' "$current_assigned_for_sub" | awk 'NF'))

	to_assign=()
	while IFS= read -r line; do
		[ -n "$line" ] && to_assign+=("$line")
	done <<<"$to_assign_raw"

	to_assign_count=${#to_assign[@]}
	already_assigned_count=$((member_count - to_assign_count))
	TOTAL_ALREADY_ASSIGNED=$((TOTAL_ALREADY_ASSIGNED + already_assigned_count))

	if [ "$to_assign_count" -eq 0 ]; then
		log SUCCESS "All ${member_count} member(s) already have subscription ${subscription_id} — no API calls needed ✓"
		continue
	fi

	log INFO "Found ${member_count} member(s): ${already_assigned_count} already licensed, ${to_assign_count} need assignment"

	# Process in batches
	for ((j = 0; j < to_assign_count; j += BATCH_SIZE)); do
		batch=("${to_assign[@]:j:BATCH_SIZE}")
		batch_num=$(((j / BATCH_SIZE) + 1))
		total_batches=$(((to_assign_count + BATCH_SIZE - 1) / BATCH_SIZE))

		log INFO "Assigning batch ${batch_num}/${total_batches} (${#batch[@]} users)..."
		if assign_licenses_batch "$subscription_id" "${batch[@]}"; then
			TOTAL_ASSIGNED=$((TOTAL_ASSIGNED + ${#batch[@]}))
			# Update snapshot file so subsequent groups know these users now have this subscription
			if [ "$DRY_RUN" = false ]; then
				for email in "${batch[@]}"; do
					printf '%s\t%s\n' "$email" "$subscription_id" >>"$CURRENT_LICENSES_FILE"
				done
			fi
		else
			TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
		fi

		if [ "$batch_num" -lt "$total_batches" ]; then
			sleep 1
		fi
	done
done

# === RECONCILE (revoke licenses for users no longer in their group) ===
# The groups are authoritative for the whole user store: every assigned seat is
# reconciled, whether its subscription appears in config.json or not. An edition
# mapped in config.json is judged against its own group; anything else — another
# subscription, or a seat with no subscription attached — has no group of its
# own and is judged against the union of every group.
if [ "$DELETE_UNASSIGNED" = true ]; then
	log HEADER ""
	log HEADER "Reconciling — revoking licenses for users no longer in their group"

	# Refresh snapshot after assignments if live updates were made. Refresh into a
	# side file and swap on success: a failed fetch redirected straight into the
	# snapshot would wipe the local tracking we fall back on.
	if [ "$TOTAL_ASSIGNED" -gt 0 ] && [ "$DRY_RUN" = false ]; then
		log INFO "Refreshing license snapshot after assignments..."
		if get_all_assigned_licenses >"$REFRESHED_LICENSES_FILE"; then
			mv "$REFRESHED_LICENSES_FILE" "$CURRENT_LICENSES_FILE"
		else
			log WARN "Could not refresh snapshot; proceeding with local tracking."
		fi
	fi

	# All desired users across ALL configured groups (used to protect users moving between editions)
	all_desired_users=$(awk -F'\t' '$2 != "" {print tolower($2)}' "$DESIRED_FILE" | awk 'NF' | LC_ALL=C sort -u)

	# Seats outside config.json are judged against that union, so revoking them is
	# only safe when it is complete — one unreadable group and a legitimate user
	# looks like a leaver. Mapped editions still reconcile against their own group.
	reconcile_unmanaged=true
	if [ "$GROUP_FETCH_FAILURES" -gt 0 ]; then
		reconcile_unmanaged=false
		log WARN "Reconciling only the editions in config.json: ${GROUP_FETCH_FAILURES} group(s) could not be read."
	fi

	while IFS= read -r cfg; do
		[ -z "$cfg" ] && continue

		cfg_label="Config ${cfg}"
		if [ "$cfg" = "$NO_SUBSCRIPTION" ]; then
			cfg_label="Seats with no subscription attached"
		elif ! printf '%s\n' "$managed_subscriptions" | grep -qxF -- "$cfg"; then
			cfg_label="Config ${cfg} (not in config.json)"
		fi

		cfg_assigned=$(awk -F'\t' -v c="$cfg" '$2 == c {print tolower($1)}' "$CURRENT_LICENSES_FILE" | awk 'NF' | LC_ALL=C sort -u)
		cfg_desired=$(awk -F'\t' -v c="$cfg" '$1 == c && $2 != "" {print tolower($2)}' "$DESIRED_FILE" | awk 'NF' | LC_ALL=C sort -u)

		# Candidate leavers for this edition: assigned to cfg, but not in cfg's group
		candidate_leavers=$(comm -23 \
			<(printf '%s\n' "$cfg_assigned" | awk 'NF') \
			<(printf '%s\n' "$cfg_desired" | awk 'NF'))

		# Safety check: do NOT revoke anyone who belongs to ANY configured group
		# (e.g., users who moved to another edition)
		leavers_raw=$(comm -23 \
			<(printf '%s\n' "$candidate_leavers" | awk 'NF') \
			<(printf '%s\n' "$all_desired_users" | awk 'NF'))

		# Report users protected by the "belongs to some group" safety check
		protected_users=$(comm -12 \
			<(printf '%s\n' "$candidate_leavers" | awk 'NF') \
			<(printf '%s\n' "$all_desired_users" | awk 'NF'))

		if [ -n "$protected_users" ]; then
			protected_count=$(printf '%s\n' "$protected_users" | awk 'NF' | wc -l | tr -d ' ')
			if [ "$protected_count" -gt 0 ]; then
				log INFO "${cfg_label}: kept ${protected_count} user(s) who are still in a configured group"
			fi
		fi

		leavers=()
		while IFS= read -r leaver; do
			[ -n "$leaver" ] && leavers+=("$leaver")
		done <<<"$leavers_raw"

		leaver_count=${#leavers[@]}
		if [ "$leaver_count" -eq 0 ]; then
			log INFO "${cfg_label}: nothing to revoke"
			continue
		fi

		log WARN "${cfg_label}: revoking ${leaver_count} license(s)"
		for ((j = 0; j < leaver_count; j += BATCH_SIZE)); do
			batch=("${leavers[@]:j:BATCH_SIZE}")
			if unassign_licenses_batch "$cfg" "${batch[@]}"; then
				TOTAL_REVOKED=$((TOTAL_REVOKED + ${#batch[@]}))
			else
				TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
			fi
			sleep 1
		done
	done < <({
		cut -f1 "$DESIRED_FILE" | awk 'NF'
		if [ "$reconcile_unmanaged" = true ]; then awk -F'\t' 'NF {print $2}' "$CURRENT_LICENSES_FILE"; fi
	} | awk 'NF' | LC_ALL=C sort -u)
fi

echo ""
log HEADER "=========================================="
log HEADER "Sync complete."
log NONE "Total members checked:  ${TOTAL_MEMBERS_CHECKED}"
log NONE "Already licensed:       ${TOTAL_ALREADY_ASSIGNED}"
log SUCCESS "New licenses assigned:  ${TOTAL_ASSIGNED}"
log SUCCESS "Licenses revoked:       ${TOTAL_REVOKED}"
if [ "$TOTAL_ERRORS" -gt 0 ]; then
	log ERROR "Batch errors:           ${TOTAL_ERRORS}"
fi
if [ "$DRY_RUN" = true ]; then
	log WARN "*** This was a dry run — no changes were made ***"
fi
log INFO "Log saved to: ${LOG_FILE}"
log HEADER "=========================================="

# Exit with non-zero if there were errors
if [ "$TOTAL_ERRORS" -gt 0 ]; then
	exit 1
fi
