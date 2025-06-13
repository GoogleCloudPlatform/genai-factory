#!/bin/bash
set -e

source ./scripts/terraform_utils.sh

# Read Terraform Outputs
export AGENT_VARIANT=$(read_tf_output "agent_variant")
export AGENT_REMOTE=$(read_tf_output "agent_remote")

agentutil pull_agent $AGENT_REMOTE agents/$AGENT_VARIANT
