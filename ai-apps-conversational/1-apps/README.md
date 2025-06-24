# AI Applications - Conversational Agents (Dialogflow) / Platform Deployment

This module is part of the `AI Applications - Conversational Agents (Dialogflow)`.
It is responsible for deploying the components enabling the AI use case, either in the project you created in [0-projects](../0-projects) or in an existing project.

![Architecture Diagram](../diagram.png)

## Deploy the module

This assumes you have created a project leveraging the [0-projects](../0-projects) module.

```shell
cp terraform.tfvars.sample terraform.tfvars # Customize
terraform init
terraform apply

# Follow the commands at screen to:
# - Push some sample data to the ds GCS bucket and load it into the data stores
# - Build the agent and push it to the chat engine (Dialogflow CX)
# - Query the agent
```

## I have not used 0-projects

The [0-projects](../0-projects) module also produces the Terraform input files needed for this stage to work. If you are not leveraging [0-projects](../0-projects) it's your responsibility to create the `terraform.tfvars` file, reflecting what's requested by [variables.tf](./variables.tf) in this module.

## Manage agent variants

- A copy of your (default variant) agent configuration is available in the `data/agents` folder.
- After you apply `1-apps`, you'll see commands build the agent and push it to Dialogflow CX.
- You can define more agent variants by creating your configuration directory in `data/agents` and updating the Terraform variable `agent_configs.variant`. Output commands to build the agent will be automatically updated.

## Pull remote agents

You can pull remote copies of your agent variants into your `data/agents` directory by using this command:

```shell
uv run tools/agentutil.py pull_agent {AGENT_REMOTE} data/agents/{AGENT_VARIANT}
```
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [project_config](variables.tf#L39) | The project where to create the resources. | <code title="object&#40;&#123;&#10;  id     &#61; string&#10;  number &#61; string&#10;  prefix &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [agent_configs](variables.tf#L15) | The AI Applications Dialogflow agent configurations. | <code title="object&#40;&#123;&#10;  language &#61; optional&#40;string, &#34;en&#34;&#41;&#10;  variant  &#61; optional&#40;string, &#34;default&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L25) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [name](variables.tf#L32) | The name of the resources. This is also the project suffix if a new project is created. | <code>string</code> |  | <code>&#34;gf-ai-apps-df-0&#34;</code> |
| [region](variables.tf#L49) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [region_ai_applications](variables.tf#L56) | The GCP region where to deploy the data store and Dialogflow. | <code>string</code> |  | <code>&#34;global&#34;</code> |
| [service_accounts](variables.tf#L63) | The pre-created service accounts used by the blueprint. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [commands](outputs.tf#L33) | Run these commands to complete the deployment. |  |
<!-- END TFDOC -->
