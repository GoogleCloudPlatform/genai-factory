# Single Cloud Run

The factory deploys a secure Cloud Run instance to run AI applications and agents.

![Architecture Diagram](./diagram.png)

## Applications

After the [1-apps](1-apps/README.md) deployment finishes, the commands to deploy the applications will be displayed at screen.

Cloud run single allows deploying these applications:

- **Chat:** a secure backend exposing a JSON interface to communicate with Gemini through Vertex APIs.
- **ADK:** a sample, secure [Agent Development Kit (ADK) deployment](./1-apps/apps/adk/README.md).
- **ADK with A2A:** a sample, secure [Agent Development Kit (ADK) deployment exposed with A2A](./1-apps/apps/adk-a2a/README.md).
- **Gemma:** a sample deployment of Gemma 3 using Cloud Run GPUs.
- **MCP Server:** a sample, custom Model Context Protocol (MCP) server to manage GCP Firewall rules by impersonating the user calling the server.

## Core Components

The deployment includes:

- An instance of **Cloud Run** (with authentication and direct VPC egress)

- An **exposure layer**, made of:
  - A **Global external application load balancer** (+ Cloud Armor IP allowlist security backend policy + HTTP to HTTPS redirect + managed certificates). This is created by default.
  - An **Internal application load balancer** (+ Cloud Armor IP allowlist security backend policy + HTTP to HTTPS redirect + managed certificates + CAS + Cloud DNS private zone). This is optional.

- By default, a **host project**, a **shared VPC**, a subnet, private Google APIs routes and DNS policies. Optionally, you can use your own host project and shared VPCs.

- A **service project** with all the necessary APIs, service accounts, permissions set.

## Apply the factory

- Enter the [0-prereqs](0-prereqs/README.md) folder and follow the instructions to setup the GCP projects, service accounts and permissions.
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the components inside the service project.
