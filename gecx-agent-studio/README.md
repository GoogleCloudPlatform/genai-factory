# Gemini Enterprise for Customer Experience (GECX) - CX Agent Studio

This factory automates the deployment of a [CX Agent Studio](https://cloud.google.com/products/gemini-enterprise-for-customer-experience/agent-studio) application connected to an unstructured [data store](https://docs.cloud.google.com/customer-engagement-ai/conversational-agents/ps/tool/data-store), backed by a [Google Cloud Storage (GCS)](https://cloud.google.com/storage/docs/introduction) bucket.

![Architecture Diagram](./diagram.png)

## Core Components

The deployment includes:

- A **CX Agent Studio** application: the conversational agent builder.
- An unstructured **data store** that indexes and serves content to the agent.
- A **GCS bucket** that stores and loads the agent configuration and the source files for the data store ingestion.

It complements the factory a script to ingest documents in the datastore and to deploy the application.

## Apply the factory

- Navigate to the [0-prereqs](0-prereqs/README.md). Follow the instructions to provision the GCP project, configure required APIs, and set up Service Accounts with the necessary IAM permissions.
- Navigate to the [1-apps](1-apps/README.md). Follow the instructions to deploy the above-mentioned components.
- Follow the commands at screen.
