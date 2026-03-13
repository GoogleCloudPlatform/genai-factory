# Natural Language to Structured Query Language (NL2SQL) with BigQuery

The factory deploys a secure Cloud Run instance to run AI applications serving a Natural Language to Structured Query Language (NL2SQL) agent based on ADK and using BigQuery as the knowledge base.

![Architecture Diagram](./diagram.png)

## Applications

After the [1-apps](1-apps/README.md) deployment finishes, the commands to deploy the applications will be displayed on your screen.

> [!NOTE]
> The commands in the Terraform output reference the public dataset [`bigquery-public-data.thelook_ecommerce.orders`](https://console.cloud.google.com/bigquery?p=bigquery-public-data&d=thelook_ecommerce&page=dataset).

> [!TIP]
> To improve performance and accuracy when using your own datasets, ensure you have populated the **column descriptions** in BigQuery, as the agent uses them to understand the schema better.

## Core Components

The deployment includes:

- An **exposure layer**, made of:
  - **Global external application load balancer** (+ Cloud Armor IP allowlist security backend policy + HTTP to HTTPS redirect + managed certificates). This is created by default.
  - **Internal application load balancer** (+ Cloud Armor IP allowlist security backend policy + HTTP to HTTPS redirect + managed certificates + CAS + Cloud DNS private zone). This is optional.

- **Cloud Run** (with authentication and direct VPC egress)

- By default, a **VPC**, a subnet, private Google APIs routes and DNS policies. Optionally, can use your existing VPCs.
- By default, a **project** with all the necessary permissions. Optionally, can use your existing project.

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the components inside the project
