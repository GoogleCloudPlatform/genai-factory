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
# Gemini Enterprise License Helpers
# Discovery and verification utilities for Gemini Enterprise subscriptions
#
# Usage: ./gemini-helpers.sh [--project <id>] [--location <loc>] [--config <path>] <command>
#
# Commands:
#   check-prereqs       Verify gcloud, curl, jq, and authentication
#   get-project-number  Look up numeric project number from project ID
#   list-configs        List all license config IDs and edition info
#   list-licenses       List currently assigned user licenses
#   find-user <email>   Show the raw license record for one user
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_QUOTA_PROJECT_ID="${QUOTA_PROJECT_ID:-}"
ENV_PROJECT_ID="${PROJECT_ID:-}"
ENV_LOCATION="${LOCATION:-}"
ENV_ENDPOINT_LOCATION="${ENDPOINT_LOCATION:-}"

TARGET_PROJECT=""
LOCATION_OVERRIDE=""
CONFIG_OVERRIDE=""
POSITIONAL_ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
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
	--location)
		if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
			echo "ERROR: --location requires a location argument (e.g. global, us, eu)."
			exit 1
		fi
		LOCATION_OVERRIDE="$2"
		shift
		;;
	--location=*)
		LOCATION_OVERRIDE="${1#*=}"
		if [ -z "$LOCATION_OVERRIDE" ]; then
			echo "ERROR: --location requires a non-empty location."
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
		POSITIONAL_ARGS+=("help")
		;;
	*)
		POSITIONAL_ARGS+=("$1")
		;;
	esac
	shift
done

CONFIG_FILE="${CONFIG_OVERRIDE:-${SCRIPT_DIR}/config.json}"
CONFIG_QUOTA_PROJECT_ID=""
PROJECT_CONFIGS=()

PROJECT_ID=""
LOCATION="global"
ENDPOINT_LOCATION="global"

_get_quota_project() {
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

_is_placeholder_project() {
	local pid="$1"
	[ -z "$pid" ] || [ "$pid" = "your-project-id" ] || [[ "$pid" == your-*-project-id ]] || [[ "$pid" == PROJECT_ID_* ]]
}

if command -v jq &>/dev/null && [ -f "$CONFIG_FILE" ]; then
	if jq -e 'type == "object" and (.projects | type == "array")' "$CONFIG_FILE" >/dev/null 2>&1; then
		CONFIG_QUOTA_PROJECT_ID=$(jq -r '.quota_project_id // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
		while IFS= read -r _pjson; do
			[ -n "$_pjson" ] && PROJECT_CONFIGS+=("$_pjson")
		done < <(jq -c '.projects[]' "$CONFIG_FILE" 2>/dev/null || true)
	elif jq -e 'type == "object" and (has("projects") | not) and (has("project_id") or has("group_mappings"))' "$CONFIG_FILE" >/dev/null 2>&1; then
		echo "  WARNING: Legacy single-project config format detected in ${CONFIG_FILE}." >&2
		echo "           Please migrate to the top-level \"projects\" array (see config.json.example)." >&2
		CONFIG_QUOTA_PROJECT_ID=$(jq -r '.quota_project_id // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
		_legacy_json=$(jq -c '.' "$CONFIG_FILE" 2>/dev/null || true)
		[ -n "$_legacy_json" ] && PROJECT_CONFIGS+=("$_legacy_json")
	fi
fi

# --- Helpers ---

_header() {
	echo ""
	echo "=== $1 ==="
	echo ""
}

_project_header() {
	echo ""
	echo "--- Project: ${PROJECT_ID} (location: ${LOCATION}, quota: $(_get_quota_project)) ---"
}

_require_gcloud() {
	if ! command -v gcloud &>/dev/null; then
		echo "ERROR: gcloud is not installed. Install the Google Cloud SDK first."
		echo "       https://cloud.google.com/sdk/docs/install"
		exit 1
	fi
}

_require_curl() {
	if ! command -v curl &>/dev/null; then
		echo "ERROR: curl is not installed."
		exit 1
	fi
}

_require_jq() {
	if ! command -v jq &>/dev/null; then
		echo "ERROR: jq is not installed. Please install jq first."
		exit 1
	fi
}

_require_auth() {
	if ! gcloud auth print-access-token &>/dev/null; then
		echo "ERROR: gcloud is not authenticated. Run: gcloud auth login"
		exit 1
	fi
}

# Resolves TARGET_ENTRIES=() array of compact JSON objects "{project_id, location, endpoint_location}"
TARGET_ENTRIES=()
_resolve_targets() {
	_require_jq
	TARGET_ENTRIES=()

	local default_loc="${ENV_LOCATION:-global}"
	local default_eloc="${ENV_ENDPOINT_LOCATION:-$default_loc}"
	if [ ${#PROJECT_CONFIGS[@]} -gt 0 ]; then
		default_loc=$(printf '%s' "${PROJECT_CONFIGS[0]}" | jq -r '.location // "global"')
		default_eloc=$(printf '%s' "${PROJECT_CONFIGS[0]}" | jq -r '.endpoint_location // .location // "global"')
	fi

	if [ -n "$TARGET_PROJECT" ]; then
		local idx pid matched=0
		if [ ${#PROJECT_CONFIGS[@]} -gt 0 ]; then
			for idx in "${!PROJECT_CONFIGS[@]}"; do
				pid=$(printf '%s' "${PROJECT_CONFIGS[$idx]}" | jq -r '.project_id // ""')
				if [ "$pid" = "$TARGET_PROJECT" ]; then
					if [ -n "$LOCATION_OVERRIDE" ]; then
						TARGET_ENTRIES+=("$(printf '%s' "${PROJECT_CONFIGS[$idx]}" | jq -c --arg l "$LOCATION_OVERRIDE" '.location = $l | .endpoint_location = $l')")
					else
						TARGET_ENTRIES+=("${PROJECT_CONFIGS[$idx]}")
					fi
					matched=1
				fi
			done
		fi
		# Allow inspecting an arbitrary --project <id> not yet in config.json
		if [ "$matched" -eq 0 ]; then
			local loc="${LOCATION_OVERRIDE:-$default_loc}"
			local eloc="${LOCATION_OVERRIDE:-$default_eloc}"
			TARGET_ENTRIES+=("$(jq -c -n --arg pid "$TARGET_PROJECT" --arg l "$loc" --arg el "$eloc" '{project_id:$pid, location:$l, endpoint_location:$el}')")
		fi
		return 0
	fi

	if [ ${#PROJECT_CONFIGS[@]} -gt 0 ]; then
		local idx pid
		for idx in "${!PROJECT_CONFIGS[@]}"; do
			pid=$(printf '%s' "${PROJECT_CONFIGS[$idx]}" | jq -r '.project_id // ""')
			if ! _is_placeholder_project "$pid"; then
				if [ -n "$LOCATION_OVERRIDE" ]; then
					TARGET_ENTRIES+=("$(printf '%s' "${PROJECT_CONFIGS[$idx]}" | jq -c --arg l "$LOCATION_OVERRIDE" '.location = $l | .endpoint_location = $l')")
				else
					TARGET_ENTRIES+=("${PROJECT_CONFIGS[$idx]}")
				fi
			fi
		done
		if [ ${#TARGET_ENTRIES[@]} -gt 0 ]; then
			return 0
		fi
	fi

	if ! _is_placeholder_project "$ENV_PROJECT_ID"; then
		local loc="${LOCATION_OVERRIDE:-$default_loc}"
		local eloc="${LOCATION_OVERRIDE:-$default_eloc}"
		TARGET_ENTRIES+=("$(jq -c -n --arg pid "$ENV_PROJECT_ID" --arg l "$loc" --arg el "$eloc" '{project_id:$pid, location:$l, endpoint_location:$el}')")
		return 0
	fi

	# Fallback to active gcloud project when config.json is absent or contains only placeholders
	local active_pid
	active_pid=$(gcloud config get-value project 2>/dev/null || echo "")
	if [ -z "$active_pid" ]; then
		echo "  ERROR: Could not determine target project."
		echo "         Configure projects in config.json, pass --project <id>, or run: gcloud config set project YOUR_PROJECT"
		exit 1
	fi
	echo "  ℹ Auto-discovered active gcloud Project ID: $active_pid"
	local loc="${LOCATION_OVERRIDE:-$default_loc}"
	local eloc="${LOCATION_OVERRIDE:-$default_eloc}"
	TARGET_ENTRIES+=("$(jq -c -n --arg pid "$active_pid" --arg l "$loc" --arg el "$eloc" '{project_id:$pid, location:$l, endpoint_location:$el}')")
}

_load_target_entry() {
	local entry_json="$1"
	PROJECT_ID=$(printf '%s' "$entry_json" | jq -r '.project_id // ""')
	LOCATION=$(printf '%s' "$entry_json" | jq -r '.location // "global"')
	ENDPOINT_LOCATION=$(printf '%s' "$entry_json" | jq -r '.endpoint_location // .location // "global"')
}

# --- Commands ---

cmd_check_prereqs() {
	_header "Checking prerequisites"

	local ok=true

	printf "  gcloud CLI ........... "
	if command -v gcloud &>/dev/null; then
		echo "✓ $(gcloud version 2>/dev/null | head -1)"
	else
		echo "✗ NOT FOUND"
		ok=false
	fi

	printf "  curl ................. "
	if command -v curl &>/dev/null; then
		echo "✓ installed"
	else
		echo "✗ NOT FOUND"
		ok=false
	fi

	printf "  python3 .............. "
	if command -v python3 &>/dev/null; then
		echo "✓ installed (optional, for JSON formatting)"
	else
		echo "- not found (optional)"
	fi

	printf "  jq ................... "
	if command -v jq &>/dev/null; then
		echo "✓ installed"
	else
		echo "✗ NOT FOUND (required for multi-project configs)"
		ok=false
	fi

	printf "  gcloud auth .......... "
	if gcloud auth print-access-token &>/dev/null 2>&1; then
		local account
		account=$(gcloud config get-value account 2>/dev/null)
		echo "✓ authenticated as ${account}"
	else
		echo "✗ NOT AUTHENTICATED — run: gcloud auth login"
		ok=false
	fi

	echo ""

	if [ "$ok" = true ]; then
		_resolve_targets
		local account idx roles
		account=$(gcloud config get-value account 2>/dev/null)
		for idx in "${!TARGET_ENTRIES[@]}"; do
			_load_target_entry "${TARGET_ENTRIES[$idx]}"
			printf "  IAM (${PROJECT_ID}) ... "
			roles=$(gcloud projects get-iam-policy "$PROJECT_ID" \
				--flatten="bindings[].members" \
				--format="value(bindings.role)" \
				--filter="bindings.members:$account" 2>/dev/null || echo "")

			if echo "$roles" | grep -E 'roles/(discoveryengine\.(admin|editor)|owner|editor)' >/dev/null; then
				echo "✓ valid (Discovery Engine Admin/Editor)"
			else
				echo "⚠ WARNING: Could not verify 'roles/discoveryengine.admin' for $account on ${PROJECT_ID}."
				echo "             Assignments may fail if you lack permissions (or resourcemanager.projects.getIamPolicy)."
			fi
		done
		echo ""
	fi

	if [ "$ok" = true ]; then
		echo "All prerequisites met ✓"
	else
		echo "Some prerequisites are missing — see above."
		exit 1
	fi
}

cmd_get_project_number() {
	_header "Looking up project number(s)"
	_require_gcloud
	_require_auth

	if [ -n "${1:-}" ]; then
		TARGET_PROJECT="$1"
	fi
	_resolve_targets

	local idx number seen_pids=""
	for idx in "${!TARGET_ENTRIES[@]}"; do
		_load_target_entry "${TARGET_ENTRIES[$idx]}"
		if printf '%s\n' "$seen_pids" | grep -qxF -- "$PROJECT_ID"; then
			continue
		fi
		seen_pids="${seen_pids}${PROJECT_ID}"$'\n'

		echo "  Project ID:     ${PROJECT_ID}"
		if number=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)" 2>/dev/null) && [ -n "$number" ]; then
			echo "  Project Number: ${number}"
			echo "    \"project_number\": \"${number}\""
		else
			echo "  ERROR: Could not retrieve project number for ${PROJECT_ID}. Check project ID and IAM permissions."
			exit 1
		fi
		echo ""
	done
}

cmd_list_configs() {
	_header "Listing license configs (subscription IDs)"
	_require_gcloud
	_require_curl
	_require_jq
	_require_auth
	_resolve_targets

	local token idx
	token="$(gcloud auth print-access-token)"

	for idx in "${!TARGET_ENTRIES[@]}"; do
		_load_target_entry "${TARGET_ENTRIES[$idx]}"
		_project_header
		curl -s -X GET \
			-H "Authorization: Bearer ${token}" \
			-H "Content-Type: application/json" \
			-H "X-Goog-User-Project: $(_get_quota_project)" \
			"https://${ENDPOINT_LOCATION}-discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/userStores/default_user_store/licenseConfigsUsageStats" |
			jq -r '.licenseConfigUsageStats[]? | .licenseConfig | split("/") | last'
	done

	echo ""
	echo "  (Copy/paste the exact strings above into each project's group_mappings in config.json)"
}

cmd_list_licenses() {
	_header "Listing currently assigned user licenses"
	_require_gcloud
	_require_curl
	_require_jq
	_require_auth
	_resolve_targets

	local token idx
	token="$(gcloud auth print-access-token)"

	for idx in "${!TARGET_ENTRIES[@]}"; do
		_load_target_entry "${TARGET_ENTRIES[$idx]}"
		_project_header
		curl -s -X GET \
			-H "Authorization: Bearer ${token}" \
			-H "Content-Type: application/json" \
			-H "X-Goog-User-Project: $(_get_quota_project)" \
			"https://${ENDPOINT_LOCATION}-discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/userStores/default_user_store/userLicenses" |
			jq .
	done
}

cmd_find_user() {
	_header "Looking up one user's license record"
	_require_gcloud
	_require_curl
	_require_jq
	_require_auth

	local email="${1:-}"
	if [ -z "$email" ]; then
		echo "  Usage: $0 [--project <id>] find-user <email>"
		exit 1
	fi

	_resolve_targets

	local access_token wanted idx
	access_token="$(gcloud auth print-access-token)"
	wanted=$(echo "$email" | tr '[:upper:]' '[:lower:]')

	for idx in "${!TARGET_ENTRIES[@]}"; do
		_load_target_entry "${TARGET_ENTRIES[$idx]}"
		_project_header

		# Page through the whole store and match locally, so the diagnostic still works
		# when the server rejects a filter expression.
		local url="https://${ENDPOINT_LOCATION}-discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/userStores/default_user_store/userLicenses"
		local page_token="" found=0

		while :; do
			local resp match
			resp=$(curl -s -G \
				-H "Authorization: Bearer ${access_token}" \
				-H "X-Goog-User-Project: $(_get_quota_project)" \
				"$url" \
				--data-urlencode "pageSize=1000" \
				${page_token:+--data-urlencode "pageToken=${page_token}"})

			if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
				echo "  ERROR: $(echo "$resp" | jq -r '.error.message // "Unknown API error"')"
				break
			fi

			match=$(echo "$resp" | jq --arg e "$wanted" \
				'[.userLicenses[]? | select((.userPrincipal // "" | ascii_downcase) == $e)]')
			if [ "$(echo "$match" | jq 'length')" -gt 0 ]; then
				echo "$match" | jq '.[]'
				found=1
			fi

			page_token=$(echo "$resp" | jq -r '.nextPageToken // ""')
			[ -z "$page_token" ] && break
		done

		if [ "$found" -eq 0 ]; then
			echo "  No license record for ${email} in ${PROJECT_ID} (${LOCATION})."
			echo "  The sync can only revoke what this API returns, so it would leave this user alone."
		fi
	done
}

# --- Dispatch ---

usage() {
	echo "Usage: $0 [--project <id>] [--location <loc>] [--config <path>] <command>"
	echo ""
	echo "Commands:"
	echo "  check-prereqs              Verify gcloud, curl, jq, and authentication"
	echo "  get-project-number [<id>]  Look up numeric project number(s)"
	echo "  list-configs               List license config IDs per project"
	echo "  list-licenses              List currently assigned user licenses per project"
	echo "  find-user <email>          Show the raw license record for one user"
	echo ""
	echo "Flags:"
	echo "  --project <id>             Target a single project (in or outside config.json)"
	echo "  --location <loc>           Override location (e.g. global, us, eu)"
	echo "  --config <path>            Path to config JSON file (default: ./config.json)"
	echo ""
	echo "Configuration:"
	echo "  Reads projects[] from config.json when present (legacy flat format also supported), or falls back to --project / active gcloud project."
}

CMD="${POSITIONAL_ARGS[0]:-}"
CMD_ARG1="${POSITIONAL_ARGS[1]:-}"

case "$CMD" in
check-prereqs) cmd_check_prereqs ;;
get-project-number) cmd_get_project_number "$CMD_ARG1" ;;
list-configs) cmd_list_configs ;;
list-licenses) cmd_list_licenses ;;
find-user) cmd_find_user "$CMD_ARG1" ;;
help | --help | -h) usage ;;
*)
	echo "Unknown command: ${CMD:-<none>}"
	echo ""
	usage
	exit 1
	;;
esac
