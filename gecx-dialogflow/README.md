# Gemini Enterprise for Customer Experience (GECX) - Dialogflow CX

This factory deploys [Dialogflow CX](https://cloud.google.com/dialogflow/docs), backed by two [data stores](https://cloud.google.com/dialogflow/cx/docs/concept/data-store), both reading data (csv and json) from a [Google Cloud Storage (GCS) bucket](https://cloud.google.com/storage/docs/introduction), and optionally connecting private to a [Cloud Function](https://docs.cloud.google.com/functions/docs).

![Architecture Diagram](./diagram.png)

## Core Components

The deployment consists of the following key components:

**Dialogflow CX**
- An **FAQ data store** that stores csv files sourced from the ds GCS bucket (see below).
- A **KB data store** that stores json files sourced from the ds GCS bucket (see below).
- A **Chat Engine** ([Dialogflow CX](https://cloud.google.com/dialogflow/docs)), backed by the data stores above.

**Storage**
- A **GCS bucket (ds)** to source (csv and json) data for AI Applications data stores.
- A **GCS bucket (build)** to source the AI Applications engine (Dialogflow agent configuration) from.

**(Optional) Serverless Resources**
- A sample **Cloud Function** configured to be accessed privately and configured with direct VPC egress. The function is accessible via webhook that directly access it from the user VPC.
- **Service Directory** to implement [Private Network Access](https://docs.cloud.google.com/service-directory/docs/private-network-access-overview) and privately connect to a private IP on-premises. The blueprint uses one random private IP that users can customize.
- All the **underlying network resources**: a VPC, a subnet, a firewall policy rule for Service Directory, Private Google APIs routes and DNS response policies. Optionally, this can be your (shared) VPC.

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the components inside the project
- Follow the commands at screen
