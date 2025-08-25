# Single Cloud GPU

The factory deploys a Cloud Run service instance with an Nvidia L4 GPU attached to run AI inference workloads.

![Architecture Diagram](./diagram.png)

## Application

After the [1-apps](1-apps/README.md) deployment finishes, the commands to acccess the application will be displayed on your screen.

![App Screenshot](./screenshot.png)

## Core Components

The deployment includes:

- **Cloud Run** (with Nvidia L4 GPU, authentication and UI Sidecar Container)

- By default, a **project** with all the necessary permissions. Optionally, can use your existing project.

## Apply the factory

- Enter the [0-projects](0-projects/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the Cloud Run Service inside the project
