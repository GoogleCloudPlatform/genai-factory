# Agent Engine Factory

The factory deploys a [Vertex AI Agent Engine (aka Reasoning Engine)](https://docs.cloud.google.com/agent-builder/agent-engine/overview).

![Architecture Diagram](./diagram.png)

## Applications

After the [1-apps](1-apps/README.md) deployment finishes, the Terraform output will print the commands to interact with the agent.

## Core Components

The deployment includes:

- The **agent**, that privately access resources in your VPC.
- A custom **service account** used by your agent.
- **Firestore** to store ADK sessions and A2A tasks.
- Optionally, a VPC, the subnets you need and Secure Web Proxy (SWP), so that your agent can access the Internet through your VPC and via a proxy.

## Source code deployment

By default, the factory deploys your code by using *Agent Engine source based deployments*.
This means the agent expects a *tar.gz package*, containing your agent definition and your *requirements.txt* file.
This is the most recent way of deploying code in Agent Engine and we believe this is what most of users need to use.

In case of need, the underlying Agent Engine module also supports other ways of deploying the code.
You can find instructions directly on the [Cloud Foundation Fabric website](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/agent-engine#serialized-object-deployment).

## Firestore as a memory store

We use [Firestore](https://firebase.google.com/docs/firestore) as the default store for ADK sessions and A2A tasks.
We need this to avoid eventual consistency issues when the containers scale out.
Also, this is the tool that users most commonly use in production.
You can swap it with your own database. In this case, you'll need to remove the Firestore instantiation from Terraform and update the applications code.

## Protect access to the agent by using VPC-SC

You can protect your agent with *VPC-SC* by restricting access to the `aiplatform.googleapis.com` API.
Setting up VPC-SC is a foundational building block and it's outside the scope of this factory.

## Apply the factory

- Enter the [0-prereqs](0-prereqs/README.md) folder and follow the instructions to setup your GCP project, service accounts and permissions
- Go to the [1-apps](1-apps/README.md) folder and follow the instructions to deploy the agent
