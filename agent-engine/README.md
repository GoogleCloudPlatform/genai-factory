# Agent Engine Factory

The factory deploys a Vertex AI Reasoning Engine (Agent Engine) in unmanaged mode.

## Applications

After the [1-apps](1-apps/README.md) deployment finishes, the commands to interact with the agent will be displayed.

## Core Components

The deployment includes:

- **Vertex AI Reasoning Engine** (unmanaged)
- **GCS Bucket** for agent artifacts
- **Service Account** for the agent

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the agent
