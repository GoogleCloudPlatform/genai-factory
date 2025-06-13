# Conversational Agents Infobot

This repository contains an example setup to version, deploy, and maintain Conversational Agents.

# Concepts

* GCP Resources are defined with Terraform
* A copy of your agent is stored in the `agents/` folder.
* A build step will automaticaly update resource references (e.g. Data Store names) within the agent definitions before pushing, to keep consistency with the ones that are deployed via Terraform
* You can define arbitrary agent variants, as long as they are compatible with the Terraform definition. Each variant is stored in a `agents/<agent_variant>` folder.
* You can pull changes from an external agent into each of the variants

# Requirements

* Working `gcloud` CLI setup (https://cloud.google.com/sdk/docs/install)
* UV (https://docs.astral.sh/uv/getting-started/installation/)

# How To

## Perform a basic deployment

1. Define your environment's specs by copying the provided [env.tfvars.template](env.tfvars.template) into a new file named `<YOUR-ENV-NAME>.tfvars` and changing values accorgingly.
1. Apply infrastructure

   ```bash
   terraform init
   terraform apply -var-file=<YOUR-ENV-NAME>.tfvars
   ```
1. Follow the instructions that will be prompted

## Create isolated environments

The provided agent definition can be deployed to multiple environments, by changing the values in `.tfvars` you can choose a specific agent variant to deploy in each environment. You can create a new environment as follows:

1. Define the envoronment's specs by copying the provided [env.tfvars.template](terraform/env.tfvars.template) into a new file named `<YOUR-ENV-NAME>.tfvars` and changing values accorgingly.
1. Create a new workspace

   ```bash
   terraform workspace new <YOUR-ENV-NAME>
   ```
1. Select the right Terraform workspace

   ```bash
   terraform workspace select <YOUR-ENV-NAME>
   ```

1. Follow the same "basic deployment" instructions

## Pull changes from a remote agent

If you are maintaining a separate development copy of your agent and want to pull its content to your local versioned copy, you may do as follows:

1. Make sure you have selected the right Terraform workspace and you have ran a `terraform apply` with its `.tfvars` file.
1. Pull the agent:

   ```bash
   uv run ./scripts/pull_agent.sh
   ```

The script will read your Terraform outputs to know which agent to pull (`agent_remote`) and where to put it (`agents/${agent_variant}`).
