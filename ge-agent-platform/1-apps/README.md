# Gemini Enterprise Agent Platform / Platform Deployment

![Architecture Diagram](../diagram.png)

This stage is part of the `Gemini Enterprise Agent Platform` factory.

It is responsible for deploying the components enabling the Gemini Enterprise Agent Platform inside the service project, created in [0-prereqs](../0-prereqs/README.md) or in an existing project.

It performs the following tasks:

- Registers service endpoints in **Agent Registry**:
  - Automatically registers Google APIs (by default, Vertex AI, Dialogflow, Discovery Engine, Model Armor, Cloud Logging, Cloud Monitoring) across multiple endpoint variants (global, mTLS, regional, regional mTLS, and Regional Endpoint Protocol / REP).
  - Registers custom HTTP/gRPC endpoints defined in `var.custom_services`.
- Deploys the **Egress Agent Gateway** configured with `AGENT_TO_ANYWHERE` access path.
- Creates a Private Service Connect **(PSC) Network Attachment for Agent Gateway** and it attaches it to the Shared VPC.
- Configures Agent Gateway authorization extensions and policies:
  - **Identity-Aware Proxy (IAP)** (`REQUEST_AUTHZ`): enforces identity verification and access control on incoming requests.
  - **Model Armor** (`CONTENT_AUTHZ`): inspects and sanitizes LLM prompt requests and model responses using configured Model Armor templates.

## Deploy the stage

If you created your project(s) through [0-prereqs](../0-prereqs/README.md), you should already see a `providers.tf` and a `terraform.auto.tfvars` file in this folder.

```shell
terraform init
terraform apply
```

## Agent Gateway Authorization Policies

By default, the stage configures Agent Gateway with IAP authorization policies.
This allows you to govern how agents (including the ones from Gemini Enterprise app) access other agents and other resources, such as custom endpoints, Google APIs and MCP servers.

Optionally, you can also enable Model Armor polices to sanitize requests and replies transiting through the gateway.

You can customize the behavior by using the variables `var.agent_gateway_config` and `var.model_armor_template_config`.

For example, you may add this configuration in your `terraform.tfvars`:

```hcl
agent_gateway_config = {
  iap = {
    enable               = true
    iam_enforcement_mode = "DRY_RUN"
    policy_version       = "V2"
  }
  model_armor = {
    enable = true
    # Optional: scope to specific host headers
    # authz_hosts = ["example.internal"]
  }
}
```

## Setting Up Custom Services in Agent Registry

You can register your services in Agent Registry, including Google APIs, your REST APIs and MCP servers by setting the `agent_registry_services` variable:

```hcl
agent_registry_services = {
  weather = {
    display_name = "Weather API Service"
    description  = "Internal weather forecast service"
    url          = "https://weather.example.com"
    # Optional: 'endpoint' (default), 'agent' or 'mcp_server'
    type = "endpoint"
  }
  weather-mcp = {
    display_name = "Weather MCP Server"
    description  = "Internal weather forecast MCP server"
    url          = "https://weather-mcp.example.com"
    type         = "mcp_server"
    # Required for the 'agent' and 'mcp_server' types
    content = file("specs/weather-mcp.json")
  }
}
```

## Manage prerequisites independently

The [0-prereqs stage](../0-prereqs/README.md) generates the necessary Terraform input files for this stage. If you manage prerequisites independently (without the [0-prereqs stage](../0-prereqs/README.md)), you'll need to manually set values for your variables in a `terraform.tfvars` file (by following what is defined in [variables.tf](./variables.tf)), and provide a `providers.tf` file.

You can look at the template files ([1](../0-prereqs/templates/providers.tf.tpl), [2](../0-prereqs/templates/terraform.auto.tfvars.tpl)) and the [outputs.tf](../0-prereqs/outputs.tf) of the [0-prereqs](../0-prereqs/README.md) stage for more details about the structure of these files.

### Working with Fabric FAST

This stage is fully compatible with the latest tagged version of [Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast).
You can create your host project and network resources using your FAST networking stage, and your service project using your own FAST project factory.
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [networking_config](variables.tf#L248) | The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links. | <code title="object&#40;&#123;&#10;  subnet &#61; string&#10;  vpc    &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [project_id](variables.tf#L257) | The id of the project where to create the resources. | <code>string</code> | ✓ |  |
| [agent_gateway_config](variables.tf#L15) | Agent Gateway configuration including authorization extensions. | <code title="object&#40;&#123;&#10;  iap &#61; optional&#40;object&#40;&#123;&#10;    fail_open            &#61; optional&#40;bool, true&#41;&#10;    iam_enforcement_mode &#61; optional&#40;string, &#34;DRY_RUN&#34;&#41;&#10;    policy_version       &#61; optional&#40;string, &#34;V2&#34;&#41;&#10;    timeout              &#61; optional&#40;string, &#34;2s&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  model_armor_config &#61; optional&#40;object&#40;&#123;&#10;    authz_hosts &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;    enable      &#61; optional&#40;bool, false&#41;&#10;    fail_open   &#61; optional&#40;bool, false&#41;&#10;    timeout     &#61; optional&#40;string, &#34;2s&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [agent_registry_services](variables.tf#L34) | Custom service endpoints to register in Agent Registry, keyed by service id. | <code title="map&#40;object&#40;&#123;&#10;  url          &#61; string&#10;  content      &#61; optional&#40;string&#41;&#10;  description  &#61; optional&#40;string&#41;&#10;  display_name &#61; optional&#40;string&#41;&#10;  protocol     &#61; optional&#40;string, &#34;HTTP_JSON&#34;&#41;&#10;  type         &#61; optional&#40;string, &#34;endpoint&#34;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L76) | Whether deletion protection is enabled. | <code>bool</code> |  | <code>true</code> |
| [model_armor_template_config](variables.tf#L83) | The Model Armor configuration for templates and floor settings. | <code title="object&#40;&#123;&#10;  enabled          &#61; optional&#40;bool, true&#41;&#10;  enforcement_type &#61; optional&#40;string, &#34;INSPECT_AND_BLOCK&#34;&#41;&#10;  floor_setting &#61; optional&#40;object&#40;&#123;&#10;    enabled          &#61; optional&#40;bool, false&#41;&#10;    enforcement_type &#61; optional&#40;string, &#34;INSPECT_AND_BLOCK&#34;&#41;&#10;    logging          &#61; optional&#40;bool, true&#41;&#10;    sdp &#61; optional&#40;object&#40;&#123;&#10;      enabled &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;    malicious_uri &#61; optional&#40;object&#40;&#123;&#10;      enabled &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;    pi_and_jailbreak &#61; optional&#40;object&#40;&#123;&#10;      confidence_level &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;      enabled          &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;    rai_filters &#61; optional&#40;object&#40;&#123;&#10;      DANGEROUS         &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;      HARASSMENT        &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;      HATE_SPEECH       &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;      SEXUALLY_EXPLICIT &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  logging &#61; optional&#40;bool, true&#41;&#10;  malicious_uri &#61; optional&#40;object&#40;&#123;&#10;    enabled &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  pi_and_jailbreak &#61; optional&#40;object&#40;&#123;&#10;    confidence_level &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    enabled          &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  rai_filters &#61; optional&#40;object&#40;&#123;&#10;    DANGEROUS         &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    HARASSMENT        &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    HATE_SPEECH       &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    SEXUALLY_EXPLICIT &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  request_template_id  &#61; optional&#40;string, &#34;agw-request-template&#34;&#41;&#10;  response_template_id &#61; optional&#40;string, &#34;agw-response-template&#34;&#41;&#10;  sdp &#61; optional&#40;object&#40;&#123;&#10;    enabled &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [name](variables.tf#L241) | The name of the resources. | <code>string</code> |  | <code>&#34;geap&#34;</code> |
| [region](variables.tf#L263) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [subnet_self_links](variables-fast.tf#L15) | Shared VPCs subnet IDs. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [agent_gateway_ids](outputs.tf#L15) | The Agent Gateway ids. |  |
| [agent_registry_uri](outputs.tf#L22) | The Agent Registry URI. |  |
<!-- END TFDOC -->
