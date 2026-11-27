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
# Gemini Enterprise License Sync — container image for Cloud Run jobs.
#
# Stage 1 unpacks a pinned Google Cloud CLI and strips the components the
# script never calls (gsutil, bq, the update backup). Stage 2 keeps only bash,
# curl, jq, python3 and that trimmed CLI.
# =============================================================================

# ---- stage 1: trimmed Google Cloud CLI ----
FROM debian:trixie-slim AS gcloud

ARG GCLOUD_VERSION=585.0.0
ARG TARGETARCH=amd64

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl python3 \
 && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
      amd64) arch=x86_64 ;; \
      arm64) arch=arm ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-linux-${arch}.tar.gz" \
    | tar -xz -C /opt \
 && CLOUDSDK_PYTHON=/usr/bin/python3 /opt/google-cloud-sdk/install.sh \
      --quiet --usage-reporting=false --path-update=false --command-completion=false \
      --no-compile-python \
 && rm -rf /opt/google-cloud-sdk/.install/.backup \
           /opt/google-cloud-sdk/platform/gsutil \
           /opt/google-cloud-sdk/platform/bq \
           /opt/google-cloud-sdk/bin/gsutil \
           /opt/google-cloud-sdk/bin/bq \
           /opt/google-cloud-sdk/bin/anthoscli \
 && find /opt/google-cloud-sdk -type d -name __pycache__ -prune -exec rm -rf {} +

# ---- stage 2: runtime ----
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq python3 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --uid 1000 --create-home --home-dir /home/app app

COPY --from=gcloud /opt/google-cloud-sdk /opt/google-cloud-sdk

ENV PATH="/opt/google-cloud-sdk/bin:${PATH}" \
    CLOUDSDK_PYTHON=/usr/bin/python3 \
    CLOUDSDK_CONFIG=/tmp/gcloud \
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 \
    HOME=/home/app

WORKDIR /app
# config.json is optional: the trailing glob bakes it in when it exists in the
# build context, and is simply skipped when it doesn't (config.json.example
# always matches, so the COPY never fails on an empty glob).
COPY gemini-license-sync.sh gemini-helpers.sh entrypoint.sh config.json.example config.json* ./
RUN chmod +x /app/*.sh && chown -R app:app /app

USER app

# Cloud Run jobs never have a TTY: --no-input makes a missing config fail fast
# instead of falling through to the interactive wizard. Override with --args.
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["--no-input"]
