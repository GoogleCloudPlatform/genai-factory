# Gemini Enterprise Agent Platform

![Architecture Diagram](./diagram.png)

This factory automates the deployment of **Gemini Enterprise Agent Platform**, including **Gemini Enterprise applications and assistants**, **Custom MCP server data connectors** (with OAuth 2.0 support), an **Egress Agent Gateway** (`AGENT_TO_ANYWHERE`), **Agent Registry**, and Service Extensions authorization policies (**Identity-Aware Proxy (IAP)** for request authorization and **Model Armor** for content inspection).

## Core Components

The deployment includes:

- **Gemini Enterprise Applications & Assistants**:
  - Deploys or adopts Gemini Enterprise (`APP_TYPE_INTRANET`) search engines and their assistants.
  - Binds the Egress Agent Gateway as the default outbound gateway for each Gemini Enterprise application.
  - Manages app-level IAM bindings, automatic project-level `roles/discoveryengine.agentspaceRestrictedUser` grants, and optional Antigravity access grants.
- **Custom MCP Server Data Connectors**:
  - Provisions federated `custom_mcp` Discovery Engine data connectors for MCP servers registered in Agent Registry, routed through the Egress Agent Gateway and attached to the target Gemini Enterprise applications.
  - Supports **OAuth 2.0** authentication with client credentials resolved directly from **Secret Manager**.
- **Egress Agent Gateway**: An Agent Gateway configured with `AGENT_TO_ANYWHERE` access path, enabling agents to securely and privately communicate with external and internal endpoints via Private Service Connect (PSC). It reaches the Shared VPC through an **agent connectivity template**, configured by default to keep every flow inside the network so that the gateway fits a VPC-SC perimeter.
- **Agent Registry**: A centralized service catalog that registers:
  - **Custom Services**: Configurable custom HTTP/gRPC endpoints, A2A agents, and **Custom MCP servers** registered for agent discovery and tool use.
- **Authorization & Safety Policies**:
  - **Identity-Aware Proxy (IAP)** (`REQUEST_AUTHZ`): Enforces identity verification and access control on agent egress.
  - **Model Armor**: Directional safety templates (`user-to-ge`, `ge-to-user`, `agent-gateway-to-external`, `external-to-agent-gateway`) inspecting user prompts, assistant responses, and gateway traffic, plus optional Vertex AI floor settings.
- **Networking Stack (by default)**:
  - A **host project** with a Shared VPC, subnet, and proxy-only subnet.
  - Cloud DNS response policies for private Google APIs routing.
  - A Private Service Connect (PSC) **Network Attachment** in the service project.
  - Optionally, you can bring your own host project and Shared VPC.
- **Service Project**: Fully provisioned with required APIs (including Discovery Engine and Secret Manager), custom roles (`psc_manager` and `discoveryengineUserBusinessAiCodeOnly`), the `iac-rw` automation service account, and necessary IAM permissions.

## Apply the factory

- Navigate to the [0-prereqs](0-prereqs/README.md) folder and follow the instructions to set up your GCP projects, service accounts, custom roles, IAM bindings, and networking stack.
- Navigate to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the Gemini Enterprise applications, Custom MCP data connectors, Agent Gateway, Agent Registry services, and authorization policies.
