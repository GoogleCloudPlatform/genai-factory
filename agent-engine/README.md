# Agent Engine Factory

The factory deploys a Vertex AI Reasoning Engine (Agent Engine) in unmanaged mode.

## Applications

After the [1-apps](1-apps/README.md) deployment finishes, the commands to interact with the agent will be displayed.

## Core Components

The deployment includes:

- A **Vertex AI Reasoning Engine**, that privately access resources in your VPC.
- A custom **Service Account** for your agent.
- Optionally, a VPC, the subnets you need and a Secure Web Proxy (SWP) so that your agent can access the Internet through your VPC and via a proxy.

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the agent
