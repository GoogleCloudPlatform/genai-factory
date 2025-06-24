# AI Applications - Conversational Agents (Dialogflow)

This module deploys an [AI Applications](https://cloud.google.com/generative-ai-app-builder/docs/introduction) chat engine ([Dialogflow CX](https://cloud.google.com/dialogflow/docs)) backed by two [data stores](https://cloud.google.com/dialogflow/cx/docs/concept/data-store), both reading data (csv and json) from a [Google Cloud Storage (GCS) bucket](https://cloud.google.com/storage/docs/introduction).

![Architecture Diagram](./diagram.png)

## Core Components

The deployment consists of the following key components:

- **AI Application (Dialogflow)**
  - An **FAQ data store** that stores csv files sourced from the ds GCS bucket (see below).
  - A **KB data store** that stores json files sourced from the ds GCS bucket (see below).
  - A **Chat Engine** ([Dialogflow CX](https://cloud.google.com/dialogflow/docs)), backed by the data stores above.

- **Storage**
- A **GCS bucket (ds)** to source (csv and json) data for AI Applications data stores.
- A **GCS bucket (build)** to source the AI Applications engine (Dialogflow agent configuration) from.

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the components inside the project
- Follow the commands at screen
