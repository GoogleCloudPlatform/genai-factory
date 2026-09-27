# Agent Runtime / Platform and Agent Deployment

This stage is part of the `Agent Runtime` factory.

It performs the following tasks:

- Deploys Agent Runtime with PSC-I, connecting to the PSC network attachment provided in input.
- Deploys the agent on Agent Runtime

It is responsible for deploying resources inside the service project you created in the [0-prereqs stage](../0-prereqs/README.md) or in an existing project.

## Deploy the stage

This assumes you have created a project by leveraging the [0-prereqs](../0-prereqs) stage.

```shell
cp terraform.tfvars.sample terraform.tfvars # Customize if needed
terraform init
terraform apply

# If you want to deploy the ADK+A2A agent, run:
terraform apply \
  -var='agent_runtime_config={"class_methods": "apps/adk-a2a/class-methods.json"}'

# Follow the commands in the output.
```

## Query the agents

Once you deploy the agents, use these sample commands to test them:

- [ADK](./apps/adk/README.md)
- [A2A](./apps/adk-a2a/README.md)

## Govern the agent traffic with Agent Gateway

Set `var.agent_gateway_ids` to route the agent traffic through an [Agent Gateway](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/agent-gateway-overview): `egress` governs the calls the agent makes, `ingress` the calls it receives. Both are optional, and the agent runs without either of them.

Gateway ids come from the `agent_gateway_ids` output of the [ge-agent-platform](../../ge-agent-platform/README.md) factory:

```hcl
agent_gateway_ids = {
  egress = "projects/my-project/locations/europe-west1/agentGateways/geap"
}
```

An egress gateway only lets the agent reach destinations it is authorized for. Grant that authorization in the `ge-agent-platform` stage, naming the agent by the `agent_identity` output of this stage.

> [!IMPORTANT]
> Two API constraints apply to an agent attached to a gateway, and this stage does not satisfy the second one yet.
>
> - **PSC-I and Agent Gateway are mutually exclusive.** The API rejects `psc_interface_config` and `agent_gateway_config` together. Setting `var.agent_gateway_ids` therefore turns PSC-I off, and the agent reaches your VPC through the connectivity template of the gateway instead of through its own network attachment.
> - **The agent must use `AGENT_IDENTITY`.** This stage deploys the agent with `identity_type = "SERVICE_ACCOUNT"`, using the `gf-ar-0` account created in [0-prereqs](../0-prereqs/README.md), so attaching a gateway currently fails with `Reasoning Engine with 'agent_gateway_config' must use 'AGENT_IDENTITY' identity type`. Moving to agent identities means granting the agent roles to the identity rather than to the account, which is not yet wired here.

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
| [networking_config](variables.tf#L72) | The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links. | <code title="object&#40;&#123;&#10;  vpc &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [number](variables.tf#L80) | The project number where to create the resources. | <code>string</code> | ✓ |  |
| [prefix](variables.tf#L86) | The unique name prefix to be used for all global unique resources. | <code>string</code> | ✓ |  |
| [project_id](variables.tf#L92) | The project ID where to create the resources. | <code>string</code> | ✓ |  |
| [proxy_config](variables.tf#L98) | The proxy configuration. | <code title="object&#40;&#123;&#10;  ip_address &#61; string&#10;  port       &#61; number&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [region](variables.tf#L107) | The GCP region where to deploy the resources. | <code>string</code> | ✓ |  |
| [service_account_emails](variables.tf#L114) | The service account emails. Each element is the email of the service account or the key of the map var.service_accounts. | <code>map&#40;string&#41;</code> | ✓ |  |
| [agent_gateway_ids](variables.tf#L15) | The ids of the Agent Gateways governing the traffic to (ingress) and from (egress) the agent. Deploy them with the ge-agent-platform factory. Setting either turns PSC-I off, as the API rejects the two together: the agent then reaches the VPC through the connectivity template of the gateway. | <code title="object&#40;&#123;&#10;  egress  &#61; optional&#40;string&#41;&#10;  ingress &#61; optional&#40;string&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [agent_runtime_config](variables.tf#L25) | The agent configuration. | <code title="object&#40;&#123;&#10;  agent_framework        &#61; optional&#40;string, &#34;google-adk&#34;&#41;&#10;  class_methods          &#61; optional&#40;string&#41;&#10;  enable_adk_telemetry   &#61; optional&#40;bool, true&#41;&#10;  enable_adk_msg_capture &#61; optional&#40;bool, true&#41;&#10;  enable_psc_i           &#61; optional&#40;bool, true&#41;&#10;  max_instances          &#61; optional&#40;number, 5&#41;&#10;  min_instances          &#61; optional&#40;number, 1&#41;&#10;  python_version         &#61; optional&#40;string, &#34;3.13&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [dns_peering_configs](variables.tf#L41) | DNS peering configurations for the Agent Runtime network. | <code title="map&#40;object&#40;&#123;&#10;  target_network_name &#61; optional&#40;string&#41;&#10;  target_project_id   &#61; optional&#40;string&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code title="&#123;&#10;  &#34;.&#34; &#61; &#123;&#125;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [enable_deletion_protection](variables.tf#L52) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [name](variables.tf#L59) | The name of the agent. | <code>string</code> |  | <code>&#34;agent-0&#34;</code> |
| [network_attachment_id](variables.tf#L66) | The network attachment ID. | <code>string</code> |  | <code>null</code> |
| [service_accounts](variables-fast.tf#L18) | The service accounts created for this stage. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [source_config](variables.tf#L120) | The source file configurations. | <code title="object&#40;&#123;&#10;  app_path          &#61; optional&#40;string, &#34;.&#47;apps&#47;adk&#34;&#41;&#10;  entrypoint_module &#61; optional&#40;string, &#34;agent&#34;&#41;&#10;  entrypoint_object &#61; optional&#40;string, &#34;agent&#34;&#41;&#10;  requirements_path &#61; optional&#40;string, &#34;requirements.txt&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [vpc_self_links](variables-fast.tf#L30) | Shared VPC name => self link mappings. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [agent_id](outputs.tf#L15) | The Agent Runtime agent id. |  |
| [agent_identity](outputs.tf#L20) | The IAM principal the agent calls other services with. Use it in the Agent Registry IAM bindings of the ge-agent-platform factory. |  |
| [commands](outputs.tf#L27) | Run the following commands when the deployment finalize the setup, deploy and test your agent. |  |
<!-- END TFDOC -->
