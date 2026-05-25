# Gemini Enterprise for Customer Experience (GECX) - CX Agent Studio / Platform and Agent Deployment

This stage is part of the `# Gemini Enterprise for Customer Experience (GECX) - CX Agent Studio` factory.

It is responsible for deploying the components enabling the AI use case, either in the project you created in [0-prereqs](../0-prereqs) or in an existing project.

It performs the following tasks:

- Deploys the CX AS agent application.
- Creates an unstructured datastore backed by sample data loaded from a GCS bucket.

![Architecture Diagram](../diagram.png)

## Deploy the stage

If you created your project(s) through [0-prereqs](../0-prereqs/README.md), you should already see in this folder a `providers.tf` and a `terraform.auto.tfvars` file.

```shell
terraform init
terraform apply

# Follow the commands at screen to:
# - Push some sample data to a GCS bucket and load it into the data store
# - Build the agent and push it to GECX Agent Studio
```

## Query the agent

After you finish applying this stage, follow the commands at screen to deploy the data stores, the agent and to query it.

## Manage prerequisites independently

The [0-prereqs stage](../0-prereqs/README.md) generates the necessary Terraform input files for this stage. If you manage prerequisites independently (without the [0-prereqs stage](../0-prereqs/README.md)), you'll need to manually set values for your variables in a `terraform.tfvars` file (by following what is defined in [variables.tf](./variables.tf)), and provide a `providers.tf` file.

You can look at the template files ([1](../0-prereqs/templates/providers.tf.tpl), [2](../0-prereqs/templates/terraform.auto.tfvars.tpl)) and the [outputs.tf](../0-prereqs/outputs.tf) of the [0-prereqs](../0-prereqs/README.md) stage for more details about the structure of these files.

Do not edit the `variables-fast.tf` file. It needs to reflect FAST standards and it is used for integrating with FAST only.

### Working with Fabric FAST

This stage is fully compatible with the latest tagged version of [Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast).
You can create your host project and network resources by using your FAST networking stage, and your service project by using your own FAST project factory.
Once you have completed these operations, create your `providers.tf` file and make sure you drop your `auto.tfvars.json` files from FAST inside this folder. Finally, create your `terraform.tfvars` file and reference the keys of the maps imported from FAST.

Do not edit the `variables-fast.tf` file, as it needs to reflect FAST standard variable names.

## Manage agent variants

- A copy of your (default variant) agent configuration is available in the `data/agents` folder.
- After you apply `1-apps`, you'll see commands build the agent and push it to CX Agent Studio.
- You can define more agent variants by creating your configuration directory in `data/agents` and updating the Terraform variable `agent_configs.variant`. Output commands to build the agent will be automatically updated.

## Pull remote agents

You can pull remote copies of your agent variants into your `data/agents` directory by using this command:

```shell
uv run scripts/agentutil.py pull_agent {AGENT_REMOTE} data/agents/{AGENT_VARIANT}
```
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [prefix](variables.tf#L46) | The unique name prefix to be used for all global unique resources. | <code>string</code> | ✓ |  |
| [project_id](variables.tf#L52) | The id of the project where to create the resources. | <code>string</code> | ✓ |  |
| [service_account_emails](variables.tf#L79) | The service account emails. Each element is the email of the service account or the key of the map var.service_accounts. | <code>map&#40;string&#41;</code> | ✓ |  |
| [cx_as_configs](variables.tf#L18) | The CX Agent Studio configurations. | <code title="object&#40;&#123;&#10;  enable_cloud_logging        &#61; optional&#40;bool, true&#41;&#10;  enable_conversation_logging &#61; optional&#40;bool, true&#41;&#10;  speaking_rate               &#61; optional&#40;number, 0&#41;&#10;  supported_languages         &#61; optional&#40;list&#40;string&#41;, &#91;&#34;en-US&#34;&#93;&#41;&#10;  timezone                    &#61; optional&#40;string, &#34;Europe&#47;Rome&#34;&#41;&#10;  tool_execution_mode         &#61; optional&#40;string, &#34;PARALLEL&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L32) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [name](variables.tf#L39) | The name of the resources. | <code>string</code> |  | <code>&#34;cx-as-0&#34;</code> |
| [region](variables.tf#L58) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [region_discovery_engine](variables.tf#L65) | The GCP region where to deploy the data store and CX Agent Studio App. | <code>string</code> |  | <code>&#34;eu&#34;</code> |
| [service_accounts](variables-fast.tf#L18) | The service accounts created for this stage. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [commands](outputs.tf#L28) | Run the following commands when the deployment completes to update and manage the application. |  |
<!-- END TFDOC -->
