# Gemini Enterprise for Customer Experience (GECX) - CX Agent Studio

This factory automates the deployment of a [CX Agent Studio](https://cloud.google.com/products/gemini-enterprise-for-customer-experience/agent-studio) application connected to an unstructured [data store](https://docs.cloud.google.com/customer-engagement-ai/conversational-agents/ps/tool/data-store) backed by a [Google Cloud Storage (GCS)](https://cloud.google.com/storage/docs/introduction) bucket.

![Architecture Diagram](./diagram.png)

## Core Components

The deployment orchestrates the following Google Cloud resources:

- A **CX Agent Studio** application: the conversational agent builder.
- A **data store**: an unstructured data store that indexes and serves content to the agent.
- A **GCS bucket**: Used by admin/CI-CD processes to store and load the agent configuration and to store source files for the data store ingestion.

It complements the factory a script ingest documents in the data store and to deploy the application.

## Apply the factory

- Navigate to the [0-projects](0-projects/README.md). Follow the instructions to provision the GCP project, configure required APIs, and set up Service Accounts with the necessary IAM permissions.
- Navigate to the [1-apps](1-apps/README.md). Follow the instructions to deploy the above-mentioned components.
- Follow the commands at screen.
