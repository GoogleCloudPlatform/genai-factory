# GenAI Factory

[![Linting](https://github.com/GoogleCloudPlatform/genai-factory/actions/workflows/linting.yml/badge.svg?event=schedule)](https://github.com/GoogleCloudPlatform/genai-factory/actions/workflows/linting.yml) [![Tests](https://github.com/GoogleCloudPlatform/genai-factory/actions/workflows/tests.yml/badge.svg?event=schedule)](https://github.com/GoogleCloudPlatform/genai-factory/actions/workflows/tests.yml)

Genai-factory is a collection of **end-to-end blueprints to deploy generative AI infrastructures** in GCP, following security best-practices.

- Embraces IaC best practices. Infrastructure is implemented in [Terraform](https://developer.hashicorp.com/terraform), leveraging [Terraform resources](https://registry.terraform.io/providers/hashicorp/google/latest/docs) and [Cloud Foundations Fabric modules](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules).
- Leverages natively [shared VPCs](https://docs.cloud.google.com/vpc/docs/shared-vpc).
- Follows the least-privilege principle: no default service accounts, primitive roles, minimal permissions.
- Compatible with [Cloud Foundation Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) [project-factory](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory) and application templates.

## Cloud Foundation Fabric Compatibility

Works with Cloud Foundation Fabric [v56.1.0](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v55.2.0).
Compatibility with master is not guaranteed.

## Factories

- [Agent Engine](./agent-engine/README.md) - An instance of Agent Engine that privately access your VPC resources, accesses Internet via SWP HTTP Proxy, running [ADK](./agent-engine/1-apps/apps/adk/README.md) or [ADK with A2A support](./agent-engine/1-apps/apps/adk-a2a/README.md).
- [Single Cloud Run](./cloud-run-single/README.md) - A secure Cloud Run deployment to interact with Gemini, run an [ADK agent](./cloud-run-single/1-apps/apps/adk/README.md), an [ADK agent exposed via A2A](./cloud-run-single/1-apps/apps/adk-a2a/README.md), a self-hosted [Gemma 3](./cloud-run-single/1-apps/apps/gemma/README.md) model with Nvidia L4 GPUs or a sample [MCP server](./cloud-run-single/1-apps/apps/mcp-server/README.md)
- [Natural Language to SQL (NL2SQL)](./cloud-run-nl2sql-bq/README.md) - A secure agent on Cloud Run that allows users to securely query data from BigQuery by using a natural language.
- [RAG with Cloud Run and CloudSQL](./cloud-run-rag-cloudsql/README.md) - A "Retrieval-Augmented Generation" (RAG) system leveraging Cloud Run, Cloud SQL and BigQuery.
- [RAG with Cloud Run and AlloyDB](./cloud-run-rag-alloydb/README.md) - A "Retrieval-Augmented Generation" (RAG) system leveraging Cloud Run, AlloyDB and BigQuery.
- [RAG with Cloud Run and Vector Search](./cloud-run-rag-search/README.md) - A "Retrieval-Augmented Generation" (RAG) system leveraging Cloud Run and Vector Search.
- [AI Application search (Vector AI Search)](./ai-apps-search/README.md) - An AI-based search engine, configured to search content from a connected data store, indexing web pages from public websites.
- [GECX Agent Studio](./gecx-agent-studio/README.md) - A [Gemini Enterprise - CX Agent Studio](https://cloud.google.com/products/gemini-enterprise-for-customer-experience/agent-studio) application connected to an unstructured [data store](https://docs.cloud.google.com/customer-engagement-ai/conversational-agents/ps/tool/data-store) backed by a [GCS](https://cloud.google.com/storage/docs/introduction) bucket.
- [GECX Dialogflow)](./gecx-dialogflow/README.md) - A chat engine based on [Dialogflow CX](https://cloud.google.com/dialogflow/docs), backed by two data stores, reading csv and json data from a [GCS](https://cloud.google.com/storage/docs/introduction) bucket.

These sample infrastructure deployments and applications can be used to be further extended and to ship your own application code.

## Quickstart

The quickstart assumes you have permissions to create and manage projects and link
to the billing account.

```shell
# Enter your preferred factory, for example cloud-run-single
cd cloud-run-single

# Create the project, service accounts, and grant permissions.
cd 0-prereqs
cp terraform.tfvars.sample terraform.tfvars # Replace prefix, billing account and parent.
terraform init
terraform apply

cd ..

# Deploy the platform services.
cd 1-apps
cp terraform.tfvars.sample terraform.tfvars # Customize.
terraform init
terraform apply

# Deploy the application and follow the commands in the output.
```

## Factories Structure

Each factory contains two stages:

### 0-prereqs

It creates projects and service accounts, enables APIs, grants IAM roles and creates the networking stack (shared VPC, subnets, DNS zones, firewall policies, ...) using [Fabric FAST project application templates](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory).

The stage also creates some components in the service project to allow Terraform in [1-apps](#1-apps) to run. This includes a service account dedicated to Terraform (with least privilege roles) and a GCS bucket where to store the Terraform state. Finally, the stage creates `providers.tf` and `terraform.auto.tfvars` files in the [1-apps folder](#1-apps) so that it's ready to run.

Running this stage is optional. If you can create projects and manage shared VPCs, use it.
Alternatively, give the yaml project templates to your infrastructure team. They can use it with their [FAST project factory](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast/stages/2-project-factory) or easily derive the requirements and implement them with their own mechanism.

### 1-apps

It deploys the core platform resources within the project and the generative AI sample application on top.

If you created the project outside genai-factory (instead of using [0-prereqs](#0-prereqs)), make sure to provide the `1-apps` stage with the projects, APIs, service accounts, roles and networking components it requires. We pass these information to `1-apps` via `terraform.auto.tfvars` files that we automatically create when [0-prereqs](#0-prereqs) runs.

# Networking Configuration

By default, the [0-prereqs](#0-prereqs) stages create the networking components that the generative AI  applications need. These include shared VPCs, subnets, routes, firewall policies, DNS zones, Private Google Access (PGA), and more.

You also have the option to still create the service project through [0-prereqs](#0-prereqs) but leverage existing networking infrastructure. To do so, you can set in every [0-prereqs stage](#0-prereqs) `var.networking_config.create = false` and pass the details of your existing infrastructure.

You can find more details in the [0-prereqs stage](#0-prereqs) of each factory.

## Credits

Thanks to the [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) community for ideas, inputs and useful tools.

## Contribute

Contributions are welcome! You can follow the guidelines in the [Contributing section](./CONTRIBUTING.md).
