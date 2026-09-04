# Gemini Enterprise Agent Platform

This factory automates the deployment of **Google Cloud Agent Platform** with an **Egress Agent Gateway** (`AGENT_TO_ANYWHERE`), **Agent Registry**, and Service Extensions authorization policies (including **Model Armor** for content inspection and **Identity-Aware Proxy (IAP)** for request authorization).

## Core Components

The deployment includes:

- **Egress Agent Gateway**: An Agent Gateway configured with `AGENT_TO_ANYWHERE` access path, enabling agents to securely and privately communicate with external and internal endpoints via Private Service Connect (PSC).
- **Agent Registry**: A centralized service catalog that registers:
  - **Google APIs**: Endpoints for Vertex AI, Dialogflow, Discovery Engine, Model Armor, Cloud Logging, and Cloud Monitoring (including regional, mTLS, and Regional Endpoint Protocol variants) with JSONRPC protocol bindings.
  - **Custom Services**: Configurable custom HTTP/gRPC endpoints registered for agent discovery and tool use.
- **Dynamic Authorization Policies**:
  - **Model Armor** (`CONTENT_AUTHZ`): Inspects requests and responses using Model Armor safety templates to sanitize content and prevent data leakage.
  - **Identity-Aware Proxy (IAP)** (`REQUEST_AUTHZ`): Enforces identity verification and access control on incoming requests.
- **Networking Stack (by default)**:
  - A **host project** with a Shared VPC, subnet, and proxy-only subnet.
  - Cloud DNS response policies for private Google APIs routing.
  - A Private Service Connect (PSC) **Network Attachment** in the service project.
  - Optionally, you can bring your own host project and Shared VPC.
- **Service Project**: Fully provisioned with required APIs, the `iac-rw` automation service account, and necessary IAM permissions.

## Apply the factory

- Navigate to the [0-prereqs](0-prereqs/README.md) folder and follow the instructions to set up your GCP projects, service accounts, IAM bindings, and networking stack.
- Navigate to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the Agent Gateway, Agent Registry endpoints, and authorization policies.
