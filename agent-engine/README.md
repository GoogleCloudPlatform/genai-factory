# Agent Engine Factory

The factory deploys a Vertex AI Agent Engine (aka Reasoning Engine).

![Architecture Diagram](./diagram.png)

## Applications

After the [1-apps](1-apps/README.md) deployment finishes, the Terraform output will print the commands to interact with the agent.

## Core Components

The deployment includes:

- The **agent**, that privately access resources in your VPC.
- A custom **service account** used by your agent.
- Optionally, a VPC, the subnets you need and a Secure Web Proxy (SWP), so that your agent can access the Internet through your VPC and via a proxy.

## Protect access to the agent by using VPC-SC

You can protect your agent with *VPC-SC* by restricting access to the `aiplatform.googleapis.com` API.
Setting up VPC-SC is a foundational building block and it's outside the scope of this factory.

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the agent
