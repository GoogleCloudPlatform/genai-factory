# GenAI Factory

[![Linting](https://github.com/GoogleCloudPlatform/genai-factory/actions/workflows/linting.yml/badge.svg?event=schedule)](https://github.com/GoogleCloudPlatform/genai-factory/actions/workflows/linting.yml) [![Tests](https://github.com/GoogleCloudPlatform/genai-factory/actions/workflows/tests.yml/badge.svg?event=schedule)](https://github.com/GoogleCloudPlatform/genai-factory/actions/workflows/tests.yml)

A collection of scripts to deploy AI infrastructures and applications in GCP, following security best-practices.

- Embraces IaC best practices. Infrastructure is implemented in [Terraform](https://developer.hashicorp.com/terraform), leveraging [Terraform resources](https://registry.terraform.io/providers/hashicorp/google/latest/docs) and [Cloud Foundations Fabric modules](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules).
- Follows the least-privilege principle: no default service accounts, primitive roles, minimal permissions.
- Compatible with [Cloud Foundation Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) [project-factory](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory) and application templates.

## Factories

- [Single Cloud Run](./cloud-run-single/README.md) - A secure Cloud Run deployment to interact with Gemini and optionally deploy [ADK agents](https://google.github.io/adk-docs/deploy/cloud-run/).
- [RAG with Cloud Run and CloudSQL](./cloud-run-single/README.md) - A "Retrieval-Augmented Generation" (RAG) system leveraging Cloud Run, Cloud SQL and BigQuery.
- [RAG with Cloud Run and Vector Search](./cloud-run-rag-search/README.md) - A "Retrieval-Augmented Generation" (RAG) system leveraging Cloud Run and Vector Search.
- [AI Application search (Vector AI Search)](./ai-apps-search/README.md) - An AI-based search engine, configured to search content from a connected data store, indexing web pages from public websites.
- [AI Application conversational agent (Dialogflow CX)](./ai-apps-conversational/README.md) - A chat engine ([Dialogflow CX](https://cloud.google.com/dialogflow/docs)) backed by two data stores, reading csv and json data from a GCS bucket.

These sample infrastructure deployments and applications can be used to be further extended and to ship your own application code.

## Quickstart

The quickstart assumes you have permissions to create and manage projects and link
to the billing account.

```shell
# Enter your preferred factory, for example cloud-run-single
cd cloud-run-single

# Create the project, service accounts, and grant permissions.
cd 0-projects
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

### 0-projects

It creates projects and service accounts, enables APIs, and grants IAM roles using [Fabric FAST project application templates](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory).

Running this stage is optional. If you can create projects, use it. Alternatively, give the yaml project template to your platform team. They can use it with their [FAST project factory](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast/stages/2-project-factory) or easily derive the requirements and implement them with their own mechanism.

The stage also creates components in the same project to allow the [1-apps](#1-apps) stage to run. This includes Terraform service accounts, roles, and a state bucket. Finally, the stage writes `providers.tf` and `terraform.auto.tfvars` files in the [1-apps folder](#1-apps).

### 1-apps

It deploys the core platform resources within the project and the AI application on top.

If you created the project outside genai-factory (instead of using [0-projects](#0-projects)), make sure to provide the `1-apps` stage with the APIs, service accounts and roles it requires. Projects and service account details are passed to `1-apps` via a `terraform.auto.tfvars` file, automatically created when [0-projects](#0-projects) runs.

# Networking Configuration

By default, [1-apps](#1-apps) stages create VPCs and other networking components if these are needed by the factory infrastructure and applications. These include VPCs, subnets, routes, DNS zones, Private Google Access (PGA), and more.

You also have the option to leverage existing VPCs. In this case, it will be your responsibility to create everything needed by the application to work.

To do so, make sure your `terraform.tfvars` in [1-apps](#1-apps) contains this configuration:

```hcl
networking_config = {
  create    = false
  vpc_id    = "your-vpc-id"
  subnet = {
    name = "your-subnet-id"
  }
}
```

## Credits

Thanks to the [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) community for ideas, input, and useful tools.

## Contribute

Contributions are welcome! You can follow the guidelines in the [Contributing section](./CONTRIBUTING.md).
