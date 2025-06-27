# AI Applications - Search

This factory deploys an AI-powered search engine built with Google Cloud's [AI Applications](https://cloud.google.com/generative-ai-app-builder/docs/introduction) ([Vertex AI Search](https://cloud.google.com/generative-ai-app-builder/docs/create-datastore-ingest)). It's configured to search the content from a connected data store indexing the content from public websites.

By default, the factory indexes the [Cloud Foundation Fabric Github repository](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) content. You can change the public website it targets by updating the [ai_apps_configs variable](./1-apps/variables.tf).

it allows you to search

- programmatically, through a JSON interface (sample command returned in output)
- via the GUI (link returned in output)

![Architecture Diagram](./diagram.png)

## Core Components

The deployment consists of the following key components:

- **AI Applications**
  - A **data store** that indexes content, such as the data from this repository's website.
  - An **engine** that connects to the data store to provide search capabilities.

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the components inside the project
