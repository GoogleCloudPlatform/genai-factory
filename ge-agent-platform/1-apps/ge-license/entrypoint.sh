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
# Container entrypoint. Resolves config.json, then hands off to the sync script.
#
# Config resolution, in order:
#   1. $CONFIG_JSON      — the config as a literal JSON string (env var or secret)
#   2. $CONFIG_GCS_URI   — gs://bucket/path/config.json, copied in at startup
#   3. /app/config.json  — baked into the image, or mounted as a volume
#
# All arguments are passed through to gemini-license-sync.sh.
# =============================================================================

set -euo pipefail

CONFIG_FILE="/app/config.json"

if [ -n "${CONFIG_JSON:-}" ]; then
	printf '%s' "$CONFIG_JSON" >"$CONFIG_FILE"
	echo "Config loaded from \$CONFIG_JSON"
elif [ -n "${CONFIG_GCS_URI:-}" ]; then
	gcloud storage cp "$CONFIG_GCS_URI" "$CONFIG_FILE"
	echo "Config loaded from ${CONFIG_GCS_URI}"
fi

if [ ! -f "$CONFIG_FILE" ]; then
	echo "ERROR: no configuration found at ${CONFIG_FILE}." >&2
	echo "       Set CONFIG_JSON or CONFIG_GCS_URI, mount a config.json volume," >&2
	echo "       or bake config.json into the image." >&2
	exit 1
fi

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
	echo "ERROR: ${CONFIG_FILE} is not valid JSON." >&2
	exit 1
fi

# The script writes its timestamped log file to the working directory. Keep that
# on /tmp so the run works even when /app is mounted read-only.
cd "${LOG_DIR:-/tmp}"

exec /app/gemini-license-sync.sh "$@"
