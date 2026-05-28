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
| [networking_config](variables.tf#L58) | The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links. | <code title="object&#40;&#123;&#10;  subnet &#61; string&#10;  vpc    &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [number](variables.tf#L67) | The project number. | <code>string</code> | ✓ |  |
| [prefix](variables.tf#L73) | The unique name prefix to be used for all global unique resources. | <code>string</code> | ✓ |  |
| [project_id](variables.tf#L79) | The id of the project where to create the resources. | <code>string</code> | ✓ |  |
| [service_account_emails](variables.tf#L106) | The service account emails. Each element is the email of the service account or the key of the map var.service_accounts. | <code>map&#40;string&#41;</code> | ✓ |  |
| [service_account_ids](variables.tf#L113) | The service account ids. Each element is the id of the service account or the key of the map var.service_accounts. | <code>map&#40;string&#41;</code> | ✓ |  |
| [cloud_function_config](variables.tf#L18) | The configuration of an optional Cloud Function to reach via Service Directory. | <code title="object&#40;&#123;&#10;  bundle_path            &#61; optional&#40;string, &#34;data&#47;function&#34;&#41;&#10;  direct_vpc_egress_mode &#61; optional&#40;string, &#34;VPC_EGRESS_ALL_TRAFFIC&#34;&#41;&#10;  direct_vpc_egress_tags &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  service_invokers       &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [cx_as_configs](variables.tf#L30) | The CX Agent Studio configurations. | <code title="object&#40;&#123;&#10;  enable_cloud_logging        &#61; optional&#40;bool, true&#41;&#10;  enable_conversation_logging &#61; optional&#40;bool, true&#41;&#10;  speaking_rate               &#61; optional&#40;number, 0&#41;&#10;  supported_languages         &#61; optional&#40;list&#40;string&#41;, &#91;&#34;en-US&#34;&#93;&#41;&#10;  timezone                    &#61; optional&#40;string, &#34;Europe&#47;Rome&#34;&#41;&#10;  tool_execution_mode         &#61; optional&#40;string, &#34;PARALLEL&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L44) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [name](variables.tf#L51) | The name of the resources. | <code>string</code> |  | <code>&#34;cx-as-0&#34;</code> |
| [region](variables.tf#L85) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [region_discovery_engine](variables.tf#L92) | The GCP region where to deploy the data store and CX Agent Studio App. | <code>string</code> |  | <code>&#34;eu&#34;</code> |
| [service_accounts](variables-fast.tf#L18) | The service accounts created for this stage. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [service_directory_configs](variables.tf#L119) | The service to create in Service Directory (key is the namespace name). | <code title="map&#40;object&#40;&#123;&#10;  cloud_dns_domain &#61; optional&#40;string&#41;&#10;  endpoints &#61; optional&#40;map&#40;object&#40;&#123;&#10;    address   &#61; string&#10;    port      &#61; number&#10;    create_lb &#61; optional&#40;bool, true&#41;&#10;    metadata  &#61; optional&#40;map&#40;string&#41;, &#123;&#125;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;  services &#61; optional&#40;map&#40;object&#40;&#123;&#10;    endpoints        &#61; list&#40;string&#41;&#10;    allowed_ca_certs &#61; optional&#40;list&#40;string&#41;&#41;&#10;    metadata         &#61; optional&#40;map&#40;string&#41;, &#123;&#125;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code title="&#123;&#10;  default &#61; &#123;&#10;    cloud_dns_domain &#61; &#34;example.com&#34;&#10;    endpoints &#61; &#123;&#10;      onprem-01 &#61; &#123; &#35; TODO: make it dynamic&#10;        address &#61; &#34;10.0.0.2&#34;&#10;        port    &#61; 443&#10;      &#125;&#10;    &#125;&#10;    services &#61; &#123;&#10;      onprem &#61; &#123;&#10;        endpoints &#61; &#91;&#34;onprem-01&#34;&#93;&#10;      &#125;&#10;    &#125;&#10;  &#125;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [subnet_self_links](variables-fast.tf#L30) | Shared VPCs subnet IDs. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |
| [tool_configs](variables.tf#L154) | The configurations for the private Cloud Run tool fronted by an HTTPS ILB. | <code title="object&#40;&#123;&#10;  containers &#61; optional&#40;map&#40;any&#41;, &#123;&#10;    hello &#61; &#123;&#10;      image &#61; &#34;us-docker.pkg.dev&#47;cloudrun&#47;container&#47;hello&#34;&#10;    &#125;&#10;  &#125;&#41;&#10;  domain                        &#61; optional&#40;string, &#34;tool.internal.gcp&#34;&#41;&#10;  ca_pool_name_suffix           &#61; optional&#40;string, &#34;ca-pool&#34;&#41;&#10;  allowed_ip_ranges             &#61; optional&#40;list&#40;string&#41;, &#91;&#34;10.0.0.0&#47;8&#34;&#93;&#41;&#10;  ingress                       &#61; optional&#40;string, &#34;INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER&#34;&#41;&#10;  vpc_access_egress             &#61; optional&#40;string, &#34;ALL_TRAFFIC&#34;&#41;&#10;  vpc_access_tags               &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  gpu_zonal_redundancy_disabled &#61; optional&#40;bool, null&#41;&#10;  node_selector                 &#61; optional&#40;map&#40;string&#41;, null&#41;&#10;  max_instance_count            &#61; optional&#40;number, 10&#41;&#10;  min_instance_count            &#61; optional&#40;number, 0&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [vpc_self_links](variables-fast.tf#L38) | Shared VPC name => self link mappings. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |
| [zones](variables.tf#L177) | The three zones in the region in use. | <code>list&#40;string&#41;</code> |  | <code>&#91;&#34;b&#34;, &#34;c&#34;, &#34;d&#34;&#93;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [commands](outputs.tf#L28) | Run the following commands when the deployment completes to update and manage the application. |  |
<!-- END TFDOC -->
