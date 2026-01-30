# Vertex AI Pipeline with Private Service Connect

This module deploys a **Vertex AI Pipeline** environment designed to demonstrate secure connectivity using **Private Service Connect (PSC)** Interfaces.

![Architecture Diagram](./diagram.png)

A **Vertex AI Custom Job** runs within a Google-managed tenant project but uses a **PSC Interface** to securely access resources within your VPC, such as a private **Cloud SQL** database, and uses a **Secure Web Proxy** for controlled internet egress.

## Core Components

The deployment includes:

- **Vertex AI Custom Jobs**:
    - Configured with a **PSC Interface** (`network_attachment`) to deploy a network interface into your VPC.
    - Demonstrates reading data from **Google Cloud Storage**, processing it, and writing results to a private Cloud SQL instance.
    - Uses a **Secure Web Proxy** for any required external internet access (e.g., installing Python dependencies).

- **Databases & Storage**:
    - A private **Cloud SQL** (PostgreSQL) instance, accessed via PSC Service Attachment from the Vertex AI job.
    - A **Google Cloud Storage** bucket for pipeline artifacts and input files.

- **Networking** (optional, provided as an example but you can use your existing network configuration):
    - A **VPC** and subnet dedicated to the pipeline and proxy.
    - **Network Attachment** (`pipeline-attachment`) to accept PSC connections from Vertex AI.
    - **Secure Web Proxy (SWP)** with self-signed TLS certificates to filter/inspect egress traffic.
    - **Cloud DNS** private zones and peering configurations to allow the Vertex AI job to resolve internal addresses (e.g., `sql.goog`).

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions.
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the components inside the project.
