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
#   ./gemini-license-sync.sh                      # Sync all projects in config.json
#   ./gemini-license-sync.sh --project <id>       # Sync only one project from config.json
#   ./gemini-license-sync.sh --setup              # Force the interactive setup wizard
#   ./gemini-license-sync.sh --dry-run            # Preview changes without making API calls
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
TARGET_PROJECT=""
CONFIG_OVERRIDE=""
while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run) DRY_RUN=true ;;
	--setup) SETUP=true ;;
	--no-input) NO_INPUT=true ;;
	--project)
		if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
			echo "ERROR: --project requires a project ID argument."
			exit 1
		fi
		TARGET_PROJECT="$2"
		shift
		;;
	--project=*)
		TARGET_PROJECT="${1#*=}"
		if [ -z "$TARGET_PROJECT" ]; then
			echo "ERROR: --project requires a non-empty project ID."
			exit 1
		fi
		;;
	--config)
		if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
			echo "ERROR: --config requires a file path argument."
			exit 1
		fi
		CONFIG_OVERRIDE="$2"
		shift
		;;
	--config=*)
		CONFIG_OVERRIDE="${1#*=}"
		if [ -z "$CONFIG_OVERRIDE" ]; then
			echo "ERROR: --config requires a non-empty file path."
			exit 1
		fi
		;;
	--help | -h)
		echo "Usage: $0 [--setup] [--dry-run] [--no-input] [--project <id>] [--config <path>]"
		echo ""
		echo "  (no flags)        Sync all projects in config.json. If it's missing and"
		echo "                    you're in a terminal, the setup wizard launches."
		echo "  --project <id>    Sync only the matching project_id from config.json."
		echo "  --config <path>   Path to config JSON file (default: ./config.json)."
		echo "  --setup           Force the interactive setup wizard."
		echo "  --dry-run         Preview what would happen without making API calls."
		echo "  --no-input        Never prompt; fail if config.json is missing (for cron)."
		exit 0
		;;
	*)
		echo "Unknown flag: $1"
		echo "Usage: $0 [--setup] [--dry-run] [--no-input] [--project <id>] [--config <path>]"
		exit 1
		;;
	esac
	shift
done

# === PATHS & DEPENDENCIES ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_OVERRIDE:-${SCRIPT_DIR}/config.json}"
ENV_QUOTA_PROJECT_ID="${QUOTA_PROJECT_ID:-}"

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
CONFIG_QUOTA_PROJECT_ID=""
PROJECT_CONFIGS=()

PROJECT_ID=""
PROJECT_NUMBER=""
LOCATION="global"
ENDPOINT_LOCATION="global"
DELETE_UNASSIGNED=false
BATCH_SIZE=100
GROUP_EMAILS=()
GROUP_SUBSCRIPTIONS=()

get_quota_project() {
	if [ -n "${ENV_QUOTA_PROJECT_ID:-}" ]; then
		echo "$ENV_QUOTA_PROJECT_ID"
	elif [ -n "${CONFIG_QUOTA_PROJECT_ID:-}" ]; then
		echo "$CONFIG_QUOTA_PROJECT_ID"
	elif [ -n "${CLOUDSDK_CORE_PROJECT:-}" ]; then
		echo "$CLOUDSDK_CORE_PROJECT"
	else
		echo "$PROJECT_ID"
	fi
}

load_project_entry() {
	local proj_json="$1"
	PROJECT_ID=$(printf '%s' "$proj_json" | jq -r '.project_id // ""')
	PROJECT_NUMBER=$(printf '%s' "$proj_json" | jq -r '.project_number // ""')
	LOCATION=$(printf '%s' "$proj_json" | jq -r '.location // "global"')
	ENDPOINT_LOCATION=$(printf '%s' "$proj_json" | jq -r '.endpoint_location // "global"')
	DELETE_UNASSIGNED=$(printf '%s' "$proj_json" | jq -r 'if .delete_unassigned == null then false else .delete_unassigned end')
	BATCH_SIZE=$(printf '%s' "$proj_json" | jq -r '.batch_size // 100')

	GROUP_EMAILS=()
	GROUP_SUBSCRIPTIONS=()
	local group sub
	while IFS="=" read -r group sub; do
		if [ -n "$group" ] && [ -n "$sub" ]; then
			GROUP_EMAILS+=("$group")
			GROUP_SUBSCRIPTIONS+=("$sub")
		fi
	done < <(printf '%s' "$proj_json" | jq -r '(.group_mappings // {}) | to_entries | .[] | "\(.key)=\(.value)"' 2>/dev/null || echo "")
}

load_config_file() {
	if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
		log ERROR "Configuration file ${CONFIG_FILE} is not valid JSON."
		exit 1
	fi

	PROJECT_CONFIGS=()
	if jq -e 'type == "object" and (.projects | type == "array") and (.projects | length > 0)' "$CONFIG_FILE" >/dev/null 2>&1; then
		CONFIG_QUOTA_PROJECT_ID=$(jq -r '.quota_project_id // ""' "$CONFIG_FILE")
		local proj_json
		while IFS= read -r proj_json; do
			[ -n "$proj_json" ] && PROJECT_CONFIGS+=("$proj_json")
		done < <(jq -c '.projects[]' "$CONFIG_FILE")
	elif jq -e 'type == "object" and (has("projects") | not) and (has("project_id") or has("group_mappings"))' "$CONFIG_FILE" >/dev/null 2>&1; then
		log WARN "Legacy single-project config format detected in ${CONFIG_FILE}."
		log WARN "Wrapping into a single-entry projects[] list. Please migrate to the multi-project schema (see config.json.example)."
		CONFIG_QUOTA_PROJECT_ID=$(jq -r '.quota_project_id // ""' "$CONFIG_FILE")
		local legacy_json
		legacy_json=$(jq -c '.' "$CONFIG_FILE")
		[ -n "$legacy_json" ] && PROJECT_CONFIGS+=("$legacy_json")
	else
		log ERROR "Invalid configuration in ${CONFIG_FILE}: expected a top-level \"projects\" array with at least one project entry."
		exit 1
	fi

	if [ -n "$TARGET_PROJECT" ]; then
		local filtered=() idx pid
		for idx in "${!PROJECT_CONFIGS[@]}"; do
			pid=$(printf '%s' "${PROJECT_CONFIGS[$idx]}" | jq -r '.project_id // ""')
			[ "$pid" = "$TARGET_PROJECT" ] && filtered+=("${PROJECT_CONFIGS[$idx]}")
		done
		if [ ${#filtered[@]} -eq 0 ]; then
			log ERROR "Project '${TARGET_PROJECT}' not found in ${CONFIG_FILE}."
			local available
			available=$(jq -r '(if has("projects") then .projects else [.] end) | [.[].project_id // empty | select(length > 0)] | join(", ")' "$CONFIG_FILE")
			[ -n "$available" ] && log ERROR "Configured projects: ${available}"
			exit 1
		fi
		PROJECT_CONFIGS=("${filtered[@]}")
	fi
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

validate_all_projects() {
	local ok=true
	local count=${#PROJECT_CONFIGS[@]}
	local seen_targets=""
	local idx

	for idx in "${!PROJECT_CONFIGS[@]}"; do
		load_project_entry "${PROJECT_CONFIGS[$idx]}"
		local label="project entry #$((idx + 1))"

		# Auto-discover PROJECT_ID only when a single project entry is configured
		if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "your-project-id" ] || [[ "$PROJECT_ID" == your-*-project-id ]] || [[ "$PROJECT_ID" == PROJECT_ID_* ]]; then
			if [ "$count" -eq 1 ]; then
				log INFO "Project ID not provided in config.json. Attempting auto-discovery..."
				PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
				if [ -z "$PROJECT_ID" ]; then
					log ERROR "Could not auto-discover PROJECT_ID."
					log ERROR "Please set it in config.json or run: gcloud config set project YOUR_PROJECT"
					ok=false
				else
					log SUCCESS "Auto-discovered Project ID: $PROJECT_ID"
				fi
			else
				log ERROR "Missing or placeholder project_id in ${label}."
				ok=false
			fi
		fi

		[ -n "$PROJECT_ID" ] && label="project '${PROJECT_ID}'"

		# Reject duplicate (project_id, location) entries — under delete_unassigned they would revoke each other's users
		if [ -n "$PROJECT_ID" ]; then
			local target_key="${PROJECT_ID}@${LOCATION}"
			if printf '%s\n' "$seen_targets" | grep -qxF -- "$target_key"; then
				log ERROR "Duplicate entry for project '${PROJECT_ID}' in location '${LOCATION}'."
				log ERROR "Combine all group_mappings for the same project and location into one entry."
				ok=false
			else
				seen_targets="${seen_targets}${target_key}"$'\n'
			fi
		fi

		# Auto-discover PROJECT_NUMBER if empty or placeholder
		if [ -z "$PROJECT_NUMBER" ] || [ "$PROJECT_NUMBER" = "123456789012" ] || [[ "$PROJECT_NUMBER" == PROJECT_NUMBER_* ]]; then
			if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "your-project-id" ] && [[ "$PROJECT_ID" != your-*-project-id ]] && [[ "$PROJECT_ID" != PROJECT_ID_* ]]; then
				log INFO "[${PROJECT_ID}] Project Number not set (${PROJECT_NUMBER:-empty}). Attempting auto-discovery..."
				PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)" 2>/dev/null || echo "")
				if [ -z "$PROJECT_NUMBER" ]; then
					log ERROR "[${PROJECT_ID}] Could not auto-discover PROJECT_NUMBER."
					log ERROR "Check your IAM permissions or set project_number manually in config.json."
					ok=false
				else
					log SUCCESS "[${PROJECT_ID}] Auto-discovered Project Number: $PROJECT_NUMBER"
				fi
			else
				ok=false
			fi
		elif ! [[ "$PROJECT_NUMBER" =~ ^[0-9]+$ ]]; then
			log ERROR "[${PROJECT_ID}] Invalid project_number '${PROJECT_NUMBER}' (must be numeric)."
			ok=false
		fi

		if ! [[ "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]]; then
			log ERROR "[${PROJECT_ID}] Invalid batch_size '${BATCH_SIZE}' (must be a positive integer)."
			ok=false
		fi

		if [ ${#GROUP_EMAILS[@]} -eq 0 ]; then
			log ERROR "[${PROJECT_ID}] No group-to-subscription mappings defined."
			ok=false
		else
			local i
			for i in "${!GROUP_EMAILS[@]}"; do
				local group_email="${GROUP_EMAILS[$i]}"
				local sub_id="${GROUP_SUBSCRIPTIONS[$i]}"
				if [[ "$sub_id" == SUBSCRIPTION_ID_* ]]; then
					log WARN "[${PROJECT_ID}] Subscription ID for ${group_email} looks like a placeholder: ${sub_id}"
					log WARN "Find real IDs via: ./gemini-helpers.sh --project ${PROJECT_ID} list-configs"
					ok=false
				fi
			done
		fi

		# Persist any auto-discovered values back into PROJECT_CONFIGS
		PROJECT_CONFIGS[$idx]=$(printf '%s' "${PROJECT_CONFIGS[$idx]}" | jq -c \
			--arg pid "$PROJECT_ID" --arg pnum "$PROJECT_NUMBER" \
			'.project_id = $pid | .project_number = $pnum')
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

get_group_members_cached() {
	local group_email="$1"
	local index_file="${GROUP_CACHE_DIR}/index.tsv"
	local cache_id=""

	if [ -f "$index_file" ]; then
		cache_id=$(awk -F'\t' -v g="$group_email" '$2 == g {print $1; exit}' "$index_file")
	fi

	if [ -n "$cache_id" ] && [ -f "${GROUP_CACHE_DIR}/${cache_id}.members" ]; then
		log INFO "Using cached membership for ${group_email}" >&2
		cat "${GROUP_CACHE_DIR}/${cache_id}.members"
		return 0
	fi

	local raw next_id=1
	if ! raw=$(get_group_members "$group_email"); then
		return 1
	fi

	if [ -f "$index_file" ]; then
		next_id=$(($(wc -l <"$index_file" | tr -d ' ') + 1))
	fi
	if [ -n "$raw" ]; then
		printf '%s\n' "$raw" >"${GROUP_CACHE_DIR}/${next_id}.members"
	else
		: >"${GROUP_CACHE_DIR}/${next_id}.members"
	fi
	printf '%s\t%s\n' "$next_id" "$group_email" >>"$index_file"
	cat "${GROUP_CACHE_DIR}/${next_id}.members"
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
		-H "X-Goog-User-Project: $(get_quota_project)" \
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
			-H "X-Goog-User-Project: $(get_quota_project)" \
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
		-H "X-Goog-User-Project: $(get_quota_project)" \
		"https://${host_loc}-discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/${path_loc}/userStores/default_user_store/licenseConfigsUsageStats" |
		jq -r '.licenseConfigUsageStats[]? | .licenseConfig | split("/") | last'
}

# Replaces any "auto" subscription value with the project's license config.
# Only unambiguous when the project has exactly one config; otherwise it lists
# the choices and fails the project so the user sets an explicit ID.
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
		return 1
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
				return 1
			fi
			;;
		esac
	done
}

# === INTERACTIVE SETUP WIZARD ===

# Prompt for a value; returns the answer (or the default on empty/EOF).
_ask() {
	local prompt="$1" default="${2:-}" answer
	if [ -n "$default" ]; then
		read -r -p "${prompt} [${default}]: " answer || true
		echo "${answer:-$default}"
	else
		read -r -p "${prompt}: " answer || true
		echo "$answer"
	fi
}

# Yes/no prompt; returns 0 for yes, 1 for no. Second arg is the default (Y or N).
_ask_yn() {
	local prompt="$1" default="${2:-N}" answer hint="[y/N]"
	[ "$default" = "Y" ] && hint="[Y/n]"
	read -r -p "${prompt} ${hint}: " answer || true
	answer="${answer:-$default}"
	case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

_wiz_rule() { echo -e "${C_CYAN}--------------------------------------------------${C_RESET}"; }
_wiz_step() {
	echo ""
	_wiz_rule
	echo -e "${C_CYAN}${C_BOLD}Step $1/5 — $2${C_RESET}"
	echo ""
}

build_project_entry_json() {
	local maps="{}" idx
	for idx in "${!GROUP_EMAILS[@]}"; do
		maps=$(printf '%s' "$maps" | jq \
			--arg k "${GROUP_EMAILS[$idx]}" --arg v "${GROUP_SUBSCRIPTIONS[$idx]}" \
			'. + {($k): $v}')
	done
	jq -c -n \
		--arg pid "$PROJECT_ID" \
		--arg pnum "$PROJECT_NUMBER" \
		--arg loc "$LOCATION" \
		--arg eloc "$ENDPOINT_LOCATION" \
		--argjson del "$DELETE_UNASSIGNED" \
		--argjson bs "$BATCH_SIZE" \
		--argjson maps "$maps" \
		'{project_id:$pid, project_number:$pnum, location:$loc, endpoint_location:$eloc, delete_unassigned:$del, batch_size:$bs, group_mappings:$maps}'
}

write_config_json() {
	local projects_json="[]" idx
	for idx in "${!PROJECT_CONFIGS[@]}"; do
		projects_json=$(printf '%s' "$projects_json" | jq \
			--argjson p "${PROJECT_CONFIGS[$idx]}" '. + [$p]')
	done
	jq -n \
		--arg qp "${CONFIG_QUOTA_PROJECT_ID:-}" \
		--argjson projs "$projects_json" \
		'{quota_project_id:$qp, projects:$projs}' \
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
	echo "  editions across one or more Google Cloud projects, then assigns"
	echo "  (and optionally revokes) licenses so the group stays the source"
	echo "  of truth. Here's what happens:"
	echo ""
	echo -e "    ${C_BLUE}1.${C_RESET} Confirm one or more Google Cloud projects"
	echo -e "    ${C_RED}2.${C_RESET} Discover each project's license region & editions (subscriptions)"
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

	PROJECT_CONFIGS=()
	CONFIG_QUOTA_PROJECT_ID=""
	local proj_num=0
	while :; do
		proj_num=$((proj_num + 1))

		# --- Step 1: Project ---
		_wiz_step 1 "Google Cloud project (#${proj_num})"
		local detected_project="" detected_number=""
		if [ "$proj_num" -eq 1 ]; then
			echo "Detecting your active project from gcloud..."
			detected_project=$(gcloud config get-value project 2>/dev/null || echo "")
			if [ -n "$detected_project" ]; then
				echo -e "  ${C_GREEN}✓ Detected: ${detected_project}${C_RESET}  (press Enter to accept, or type another)"
			fi
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
		_wiz_step 2 "License region & editions (${PROJECT_ID})"
		echo -e "${C_YELLOW}Licenses are tied to a specific multi-region — pick the one where your"
		echo -e "subscription was provisioned (shown in the Cloud console under Location).${C_RESET}"
		echo ""
		echo "Probing common multi-regions for subscriptions..."
		local loc_cfg="${RUN_TMP_DIR}/wizard-locs-${proj_num}.tsv" idx
		: >"$loc_cfg"
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
			echo "A single entry manages one region."
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
		_wiz_step 3 "Map Google Groups to editions (${PROJECT_ID})"
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
			if preview=$(get_group_members_cached "$g" 2>/dev/null); then
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
			_ask_yn "Add another group for ${PROJECT_ID}?" "N" || break
		done
		if [ ${#GROUP_EMAILS[@]} -eq 0 ]; then
			echo -e "${C_RED}No mappings defined for ${PROJECT_ID} — nothing to do.${C_RESET}"
			exit 1
		fi

		# --- Step 4: Revocation policy ---
		_wiz_step 4 "Revocation policy (${PROJECT_ID})"
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

		PROJECT_CONFIGS+=("$(build_project_entry_json)")
		echo ""
		_ask_yn "Configure another Google Cloud project?" "N" || break
	done

	if [ ${#PROJECT_CONFIGS[@]} -gt 1 ] || [ -n "${CLOUDSDK_CORE_PROJECT:-}" ]; then
		echo ""
		local default_qp="${CLOUDSDK_CORE_PROJECT:-$(printf '%s' "${PROJECT_CONFIGS[0]}" | jq -r '.project_id')}"
		echo "Optional: choose a single quota project for X-Goog-User-Project across all API calls"
		echo "(leave blank to bill each project's API quota to itself)."
		CONFIG_QUOTA_PROJECT_ID=$(_ask "Quota project ID" "$default_qp")
	fi

	# --- Step 5: Review, save, run ---
	_wiz_step 5 "Review (${#PROJECT_CONFIGS[@]} project(s))"
	if [ -n "$CONFIG_QUOTA_PROJECT_ID" ]; then
		echo -e "${C_BOLD}Quota project:${C_RESET}    ${CONFIG_QUOTA_PROJECT_ID}"
		echo ""
	fi
	local p_idx m_idx
	for p_idx in "${!PROJECT_CONFIGS[@]}"; do
		load_project_entry "${PROJECT_CONFIGS[$p_idx]}"
		echo -e "${C_BOLD}Project #$((p_idx + 1)):${C_RESET}       ${PROJECT_ID} (${PROJECT_NUMBER})"
		echo -e "${C_BOLD}Location:${C_RESET}         ${LOCATION} / ${ENDPOINT_LOCATION}"
		echo -e "${C_BOLD}Revoke on leave:${C_RESET}  ${DELETE_UNASSIGNED}"
		echo -e "${C_BOLD}Mappings:${C_RESET}"
		for m_idx in "${!GROUP_EMAILS[@]}"; do
			printf "   %s → %s\n" "${GROUP_EMAILS[$m_idx]}" "${GROUP_SUBSCRIPTIONS[$m_idx]}"
		done
		echo ""
	done
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

# === BOOTSTRAP (prereqs, temp workspace, then load config from wizard or config.json) ===
check_prereqs
ACCESS_TOKEN="$(gcloud auth print-access-token)"

RUN_TMP_DIR=$(mktemp -d)
GROUP_CACHE_DIR="${RUN_TMP_DIR}/groups"
mkdir -p "$GROUP_CACHE_DIR"
trap 'rm -rf "$RUN_TMP_DIR"' EXIT

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
	validate_all_projects
fi

# === MAIN ===

GRAND_TOTAL_ASSIGNED=0
GRAND_TOTAL_REVOKED=0
GRAND_TOTAL_ERRORS=0
GRAND_TOTAL_MEMBERS_CHECKED=0
GRAND_TOTAL_ALREADY_ASSIGNED=0
SUCCEEDED_PROJECTS=0
FAILED_PROJECTS=0

sync_project() {
	local proj_idx="$1"
	local total_projects="$2"
	local proj_num=$((proj_idx + 1))

	load_project_entry "${PROJECT_CONFIGS[$proj_idx]}"

	# Refresh access token at the start of each project to avoid mid-run expiry
	if ! ACCESS_TOKEN="$(gcloud auth print-access-token 2>/dev/null)"; then
		log ERROR "[${PROJECT_ID}] Failed to refresh gcloud access token."
		GRAND_TOTAL_ERRORS=$((GRAND_TOTAL_ERRORS + 1))
		return 1
	fi

	echo ""
	log HEADER "------------------------------------------"
	log HEADER "Project [${proj_num}/${total_projects}]: ${PROJECT_ID} (${PROJECT_NUMBER})"
	log NONE "Location: ${LOCATION} | Endpoint: ${ENDPOINT_LOCATION} | Quota project: $(get_quota_project)"
	log NONE "Delete unassigned: ${DELETE_UNASSIGNED} | Batch size: ${BATCH_SIZE}"
	log HEADER "------------------------------------------"

	if ! resolve_subscriptions; then
		log ERROR "[${PROJECT_ID}] Subscription resolution failed — skipping project."
		GRAND_TOTAL_ERRORS=$((GRAND_TOTAL_ERRORS + 1))
		return 1
	fi

	local TOTAL_ASSIGNED=0
	local TOTAL_REVOKED=0
	local TOTAL_ERRORS=0
	local TOTAL_MEMBERS_CHECKED=0
	local TOTAL_ALREADY_ASSIGNED=0
	local GROUP_FETCH_FAILURES=0

	# Per-project temp files for desired assignments and current license snapshot.
	# DESIRED_FILE records "configId<TAB>email" for every desired assignment and
	# "configId<TAB>" marker per successfully-fetched group so reconcile knows
	# which editions are safe to revoke from.
	local proj_tmp="${RUN_TMP_DIR}/proj-${proj_idx}"
	mkdir -p "$proj_tmp"
	local DESIRED_FILE="${proj_tmp}/desired.tsv"
	local CURRENT_LICENSES_FILE="${proj_tmp}/current.tsv"
	local REFRESHED_LICENSES_FILE="${proj_tmp}/refreshed.tsv"
	: >"$DESIRED_FILE"
	: >"$CURRENT_LICENSES_FILE"

	log INFO "Fetching current license assignments..."
	# Without this snapshot the script cannot tell a new user from an existing one,
	# so it would re-assign everybody and revoke nobody. Skip this project instead of guessing.
	if ! get_all_assigned_licenses >"$CURRENT_LICENSES_FILE"; then
		log ERROR "[${PROJECT_ID}] Could not fetch current license assignments — aborting project"
		log ERROR "rather than re-assigning every group member against an unknown state."
		GRAND_TOTAL_ERRORS=$((GRAND_TOTAL_ERRORS + 1))
		rm -rf "$proj_tmp"
		return 1
	fi

	local initial_assigned_count unattached_count managed_subscriptions unmanaged_note seat_count cfg
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

	local i j group_email subscription_id members_raw members_sorted member_count
	local current_assigned_for_sub to_assign_raw line to_assign_count already_assigned_count
	local batch_num total_batches email
	for i in "${!GROUP_EMAILS[@]}"; do
		group_email="${GROUP_EMAILS[$i]}"
		subscription_id="${GROUP_SUBSCRIPTIONS[$i]}"
		log HEADER ""
		log HEADER "Processing group: ${group_email}"
		log NONE "  Subscription ID: ${subscription_id}"

		# Under `set -e` a failing command substitution in a bare assignment aborts the
		# script, so branch on the fetch directly to skip just this group on error.
		if ! members_raw=$(get_group_members_cached "$group_email"); then
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

		local to_assign=()
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
			local batch=("${to_assign[@]:j:BATCH_SIZE}")
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

			if [ "$batch_num" -lt "$total_batches" ] && [ "$DRY_RUN" = false ]; then
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

		local all_desired_users reconcile_unmanaged cfg_label cfg_assigned cfg_desired
		local candidate_leavers leavers_raw protected_users protected_count leaver leaver_count
		# All desired users across ALL configured groups in this project (used to protect users moving between editions)
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

			local leavers=()
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
				local batch=("${leavers[@]:j:BATCH_SIZE}")
				if unassign_licenses_batch "$cfg" "${batch[@]}"; then
					TOTAL_REVOKED=$((TOTAL_REVOKED + ${#batch[@]}))
				else
					TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
				fi
				if [ "$DRY_RUN" = false ]; then
					sleep 1
				fi
			done
		done < <({
			cut -f1 "$DESIRED_FILE" | awk 'NF'
			if [ "$reconcile_unmanaged" = true ]; then awk -F'\t' 'NF {print $2}' "$CURRENT_LICENSES_FILE"; fi
		} | awk 'NF' | LC_ALL=C sort -u)
	fi

	log HEADER ""
	log INFO "[${PROJECT_ID}] Summary — Checked: ${TOTAL_MEMBERS_CHECKED} | Already licensed: ${TOTAL_ALREADY_ASSIGNED} | Assigned: ${TOTAL_ASSIGNED} | Revoked: ${TOTAL_REVOKED} | Errors: ${TOTAL_ERRORS}"

	GRAND_TOTAL_MEMBERS_CHECKED=$((GRAND_TOTAL_MEMBERS_CHECKED + TOTAL_MEMBERS_CHECKED))
	GRAND_TOTAL_ALREADY_ASSIGNED=$((GRAND_TOTAL_ALREADY_ASSIGNED + TOTAL_ALREADY_ASSIGNED))
	GRAND_TOTAL_ASSIGNED=$((GRAND_TOTAL_ASSIGNED + TOTAL_ASSIGNED))
	GRAND_TOTAL_REVOKED=$((GRAND_TOTAL_REVOKED + TOTAL_REVOKED))
	GRAND_TOTAL_ERRORS=$((GRAND_TOTAL_ERRORS + TOTAL_ERRORS))

	rm -rf "$proj_tmp"

	if [ "$TOTAL_ERRORS" -gt 0 ]; then
		return 1
	fi
	return 0
}

TOTAL_PROJECTS=${#PROJECT_CONFIGS[@]}

echo ""
log HEADER "=========================================="
if [ "$DRY_RUN" = true ]; then
	log WARN "*** DRY RUN MODE — no changes will be made ***"
fi
log HEADER "Gemini Enterprise License Sync Starting"
log NONE "Projects to sync: ${TOTAL_PROJECTS}"
if [ -n "${ENV_QUOTA_PROJECT_ID:-${CONFIG_QUOTA_PROJECT_ID:-${CLOUDSDK_CORE_PROJECT:-}}}" ]; then
	log NONE "Quota project:    ${ENV_QUOTA_PROJECT_ID:-${CONFIG_QUOTA_PROJECT_ID:-${CLOUDSDK_CORE_PROJECT:-}}}"
fi
log HEADER "=========================================="

for proj_idx in "${!PROJECT_CONFIGS[@]}"; do
	if sync_project "$proj_idx" "$TOTAL_PROJECTS"; then
		SUCCEEDED_PROJECTS=$((SUCCEEDED_PROJECTS + 1))
	else
		FAILED_PROJECTS=$((FAILED_PROJECTS + 1))
	fi
done

echo ""
log HEADER "=========================================="
log HEADER "Sync complete (${SUCCEEDED_PROJECTS}/${TOTAL_PROJECTS} project(s) succeeded)."
if [ "$FAILED_PROJECTS" -gt 0 ]; then
	log ERROR "Projects with errors:   ${FAILED_PROJECTS}"
fi
log NONE "Total members checked:  ${GRAND_TOTAL_MEMBERS_CHECKED}"
log NONE "Already licensed:       ${GRAND_TOTAL_ALREADY_ASSIGNED}"
log SUCCESS "New licenses assigned:  ${GRAND_TOTAL_ASSIGNED}"
log SUCCESS "Licenses revoked:       ${GRAND_TOTAL_REVOKED}"
if [ "$GRAND_TOTAL_ERRORS" -gt 0 ]; then
	log ERROR "Total errors:           ${GRAND_TOTAL_ERRORS}"
fi
if [ "$DRY_RUN" = true ]; then
	log WARN "*** This was a dry run — no changes were made ***"
fi
log INFO "Log saved to: ${LOG_FILE}"
log HEADER "=========================================="

# Exit with non-zero if there were errors in any project
if [ "$FAILED_PROJECTS" -gt 0 ] || [ "$GRAND_TOTAL_ERRORS" -gt 0 ]; then
	exit 1
fi
