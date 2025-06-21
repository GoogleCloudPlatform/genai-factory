#!/bin/env bash

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

source ./scripts/terraform_utils.sh

# Read Terraform Outputs
export AGENT_VARIANT=$(read_tf_output "agent_variant")
export AGENT_REMOTE=$(read_tf_output "agent_remote")

agentutil pull_agent $AGENT_REMOTE agents/$AGENT_VARIANT
