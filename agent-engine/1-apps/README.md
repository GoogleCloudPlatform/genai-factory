# Agent Engine / Platform and Agent Deployment

This stage is part of the `Agent Engine` factory.

It performs the following tasks:

- Deploys Agent Engine with PSC-I, connecting to the PSC network attachment provided in input.
- Deploys the agent on Agent Engine

It is responsible for deploying resources inside the service project you created in the [0-prereqs stage](../0-prereqs/README.md) or in an existing project.

## Deploy the stage

This assumes you have created a project by leveraging the [0-prereqs](../0-prereqs) stage.

```shell
cp terraform.tfvars.sample terraform.tfvars # Customize if needed
terraform init
terraform apply

# If you want to deploy the ADK+A2A agent, run:
terraform apply \
  -var='agent_engine_config={"class_methods": "apps/adk-a2a/class-methods.json"}'

# Follow the commands in the output.
```

## Query the agents

Once you deploy the agents, use these sample commands to test them:

- [ADK](./apps/adk/README.md)
- [A2A](./apps/adk-a2a/README.md)

## Re-deploy or update the agent

By default, this stage deploys the agent only once because we set `managed = false` in the agent module. This setting allows you to use Terraform to manage the infrastructure while deploying the agent's code through your own application pipelines.

To trigger a deployment with Terraform while `managed = false`, delete the existing `tar.gz` agent file in `1-apps` and instruct Terraform to explicitly re-deploy the agent:

```hcl
terraform apply -replace module.agent.google_vertex_ai_reasoning_engine.unmanaged[0]
```

You can also deploy the agent by using the commands returned in the Terraform output.

Alternatively, if you set `managed = true` to fully control the deployment via Terraform, Terraform re-creates the agent every time you modify the code and apply the changes. In this case, the automatic recreation occurs because the name of the source `tar.gz` archive is the hash of all files in the agent's source directory.

## Manage prerequisites independently

The [0-prereqs stage](../0-prereqs/README.md) generates the necessary Terraform input files for this stage. If you manage prerequisites independently (without the [0-prereqs stage](../0-prereqs/README.md)), you'll need to manually set values for your variables in a `terraform.tfvars` file (by following what is defined in [variables.tf](./variables.tf)), and provide a `providers.tf` file.

You can look at the template files ([1](../0-prereqs/templates/providers.tf.tpl), [2](../0-prereqs/templates/terraform.auto.tfvars.tpl)) and the [outputs.tf](../0-prereqs/outputs.tf) of the [0-prereqs](../0-prereqs/README.md) stage for more details about the structure of these files.

Do not edit the `variables-fast.tf` file. It needs to reflect FAST standards and it is used for integrating with FAST only.

### Working with Fabric FAST

This stage is fully compatible with the latest tagged version of [Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast).
You can create your host project and network resources by using your FAST networking stage, and your service project by using your own FAST project factory.
Once you have completed these operations, create your `providers.tf` file and make sure you drop your `auto.tfvars.json` files from FAST inside this folder. Finally, create your `terraform.tfvars` file and reference the keys of the maps imported from FAST.

Do not edit the `variables-fast.tf` file, as it needs to reflect FAST standard variable names.
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [networking_config](variables.tf#L62) | The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links. | <code title="object&#40;&#123;&#10;  vpc &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [number](variables.tf#L70) | The project number where to create the resources. | <code>string</code> | ✓ |  |
| [prefix](variables.tf#L76) | The unique name prefix to be used for all global unique resources. | <code>string</code> | ✓ |  |
| [project_id](variables.tf#L82) | The project ID where to create the resources. | <code>string</code> | ✓ |  |
| [proxy_config](variables.tf#L88) | The proxy configuration. | <code title="object&#40;&#123;&#10;  ip_address &#61; string&#10;  port       &#61; number&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [region](variables.tf#L97) | The GCP region where to deploy the resources. | <code>string</code> | ✓ |  |
| [service_account_emails](variables.tf#L104) | The service account emails. Each element is the email of the service account or the key of the map var.service_accounts. | <code>map&#40;string&#41;</code> | ✓ |  |
| [agent_engine_config](variables.tf#L15) | The agent configuration. | <code title="object&#40;&#123;&#10;  agent_framework        &#61; optional&#40;string, &#34;google-adk&#34;&#41;&#10;  class_methods          &#61; optional&#40;string&#41;&#10;  enable_adk_telemetry   &#61; optional&#40;bool, true&#41;&#10;  enable_adk_msg_capture &#61; optional&#40;bool, true&#41;&#10;  enable_psc_i           &#61; optional&#40;bool, true&#41;&#10;  max_instances          &#61; optional&#40;number, 5&#41;&#10;  min_instances          &#61; optional&#40;number, 1&#41;&#10;  python_version         &#61; optional&#40;string, &#34;3.13&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [dns_peering_configs](variables.tf#L31) | DNS peering configurations for the Agent Engine network. | <code title="map&#40;object&#40;&#123;&#10;  target_network_name &#61; optional&#40;string&#41;&#10;  target_project_id   &#61; optional&#40;string&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code title="&#123;&#10;  &#34;.&#34; &#61; &#123;&#125;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [enable_deletion_protection](variables.tf#L42) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [name](variables.tf#L49) | The name of the agent. | <code>string</code> |  | <code>&#34;agent-0&#34;</code> |
| [network_attachment_id](variables.tf#L56) | The network attachment ID. | <code>string</code> |  | <code>null</code> |
| [service_accounts](variables-fast.tf#L18) | The service accounts created for this stage. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [source_config](variables.tf#L110) | The source file configurations. | <code title="object&#40;&#123;&#10;  app_path          &#61; optional&#40;string, &#34;.&#47;apps&#47;adk&#34;&#41;&#10;  entrypoint_module &#61; optional&#40;string, &#34;agent&#34;&#41;&#10;  entrypoint_object &#61; optional&#40;string, &#34;agent&#34;&#41;&#10;  requirements_path &#61; optional&#40;string, &#34;requirements.txt&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [vpc_self_links](variables-fast.tf#L30) | Shared VPC name => self link mappings. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [agent_id](outputs.tf#L15) | The agent engine agent id. |  |
| [commands](outputs.tf#L20) | Run the following commands when the deployment finalize the setup, deploy and test your agent. |  |
<!-- END TFDOC -->
