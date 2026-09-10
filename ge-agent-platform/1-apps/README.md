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
- Grants the **IAM bindings authorizing agent egress** through IAP toward the registry, the registered services, or both.

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

You can customize the behavior by using the variables `var.agent_gateway_config.egress` and `var.model_armor_template_config`.

For example, you may add this configuration in your `terraform.tfvars`:

```hcl
agent_gateway_config = {
  egress = {
    iap = {
      fail_open = false
    }
    model_armor_config = {
      enable = true
      # Optional: scope to specific host headers
      # authz_hosts = ["example.internal"]
    }
    # Registries attached to the gateway. At most two of
    # 'eu', 'global', 'regional', 'us'.
    registry_locations = ["global", "regional"]
  }
}
```

### Registry locations

An Agent Gateway resolves destination URLs against the Agent Registry instances attached to it. `var.agent_gateway_config.egress.registry_locations` selects those instances by keyword, and each keyword maps to a registry URI:

| Keyword | Registry |
|---|---|
| `eu` | the multi-regional European registry |
| `global` | the global registry |
| `regional` | the regional registry |
| `us` | the multi-regional US registry |

At most two can be attached, and the default is `["global", "regional"]`.

Regional entries take precedence over global ones when the gateway resolves a destination URL, which matters when registries in different locations hold entries with identical interface URLs.

Registry location and service location are separate settings: `registry_locations` says which registries the gateway reads, while `agent_registry_services[*].location` says where each service is registered. A service is only reachable through the gateway if its location is among the attached registries.

### Policy model

IAP evaluates agent egress against one of two mutually exclusive policy models, selected by `iapPolicyVersion` on the authorization extension. They check different permissions, so a gateway configured for one model ignores the policies of the other.

| | `V1` | `V2` |
|---|---|---|
| Model | IAM allow policies (role bindings) | [IAM Unified Access Policies](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/policies/iam-overview-uap) |
| Permission checked | `iap.webServiceVersions.egressViaIAP` | `iap.googleapis.com/resources.egressViaIAP` |
| Granted by | `roles/iap.egressor` on the destination | a rule inside an access policy |

**This stage supports `V1` only**, because the Terraform Google provider cannot yet bind the IAM v3 access policies that `V2` evaluates.

`var.agent_gateway_config.egress.iap.policy_version` defaults to `V1`, and the `agent_registry_iam*` variables described in [Authorizing agent egress](#authorizing-agent-egress) create `roles/iap.egressor` bindings, which only a `V1` gateway evaluates.

`V2` is rejected by a variable validation. Terraform can create an access policy with `google_iam_project_access_policy`, but it cannot bind one to a project: binding requires the `target.resource` field of the IAM v3 API, and `google_iam_projects_policy_binding` exposes only `target.principal_set`. An unbound access policy has no effect, so accepting `V2` here would silently disable every egress guardrail. If you need `V2`, manage the access policies and their bindings outside this stage.

### Enforcement mode

By default, IAP **enforces** the IAM policies described in [Authorizing agent egress](#authorizing-agent-egress): egress that no binding allows is blocked.

Before rolling out policies to live traffic, deploy them in audit-only mode by setting `iam_enforcement_mode` to `DRY_RUN`. In this mode IAP logs the egress it would have denied to Cloud Audit Logs, without blocking it:

```hcl
agent_gateway_config = {
  egress = {
    iap = {
      iam_enforcement_mode = "DRY_RUN"
    }
  }
}
```

Once the audit logs show no unexpected denials, remove the attribute to start enforcing. `DRY_RUN` and `null` (enforce) are the only accepted values.

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

## Authorizing agent egress

Registering a service in Agent Registry does not by itself let agents reach it. Agent Gateway checks that the calling agent identity holds the `iap.webServiceVersions.egressViaIAP` permission — granted by `roles/iap.egressor` — on the destination resource. All egress is denied unless a binding allows it, so each destination needs a binding naming the agents allowed to call it.

Agents are identified by their [agent identity](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/agent-identity-overview), not by a service account:

- Agent Runtime, Gemini Enterprise and Cloud Run agents use built-in identities, in the form `principal://TRUST_DOMAIN/AGENT_UNIQUE_IDENTIFIER` — for example `principal://agents.global.proj-1234567890.system.id.goog/resources/aiplatform/projects/1234567890/locations/europe-west1/reasoningEngines/support-agent`.
- Custom and external agents use Workload Identity Federation identities, in the form `principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/subject/SUBJECT`.

Agent identifiers in URN format (`urn:agent:...`) are used for catalog lookups only and are not valid in IAM bindings.

### Authorizing access to services registered by this stage

Every entry of `var.agent_registry_services` accepts the `iam`, `iam_bindings` and `iam_bindings_additive` attributes, so grants live next to the service they authorize.

For example, you can authorize your agent to call an external endpoint, by granting the `iap.egressor` role:

```hcl
agent_registry_services = {
  billing-api = {
    display_name = "Billing REST API"
    description  = "Internal billing service"
    url          = "https://billing.example.com"
    location     = "europe-west1"
    # Authoritative IAM binding
    iam = {
      "roles/iap.egressor" = [
        "principal://agents.global.proj-1234567890.system.id.goog/resources/aiplatform/projects/1234567890/locations/europe-west1/reasoningEngines/support-agent"
      ]
    }
  }
}
```

That single entry does three things: it registers the API in Agent Registry, it creates `google_iap_agent_registry_endpoint_iam_binding` on the resulting endpoint, and — once the gateway is enforcing — it lets `support-agent` reach `https://billing.example.com` while every other agent is denied.

The same attributes work for MCP servers and agents:

```hcl
agent_registry_services = {
  weather-mcp = {
    display_name = "Weather MCP Server"
    url          = "https://weather-mcp.example.com"
    type         = "mcp_server"
    content      = file("specs/weather-mcp.json")
    # Authoritative IAM binding
    iam = {
      "roles/iap.egressor" = [
        "principal://agents.global.proj-1234567890.system.id.goog/resources/aiplatform/projects/1234567890/locations/europe-west1/reasoningEngines/support-agent"
      ]
    }
  }
}
```

Using `iam_bindings`, you can allow access to specific MCP tools by filtering on the corresponding `iap.googleapis.com/mcp.toolName` attribute.

```hcl
agent_registry_services = {
  # Authoritative IAM binding that allows also to express conditions.
  # This allows allowing access to specific MCP tools.
  weather-mcp-readonly = {
    display_name = "Weather MCP Server (read-only tools)"
    url          = "https://weather-mcp.example.com"
    type         = "mcp_server"
    content      = file("specs/weather-mcp.json")
    iam_bindings = {
      forecast-tool-only = {
        members = [
          "principal://agents.global.proj-1234567890.system.id.goog/resources/aiplatform/projects/1234567890/locations/europe-west1/reasoningEngines/support-agent"
        ]
        role    = "roles/iap.egressor"
        condition = {
          title      = "forecast-tool-only"
          expression = "api.getAttribute('iap.googleapis.com/mcp.toolName', '') in ['get_forecast', '']"
        }
      }
    }
  }
}
```

The `destination.*` attributes documented for [IAM Access policies](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/policies/cel-attributes-uap) belong to the `V2` policy model and do not apply here.

### Authorizing access to the whole registry and to external services

Use the `var.agent_registry_iam*` variables to grant egress across the whole registry, or toward resources that this stage does not register.

```hcl
# Whole registry, in {ROLE => [MEMBERS]} format.
agent_registry_iam = {
  "roles/iap.egressor" = [
    "principal://agents.global.proj-1234567890.system.id.goog/resources/aiplatform/projects/1234567890/locations/europe-west1/reasoningEngines/support-agent"
  ]
}

# Whole registry, in {PRINCIPAL => [ROLES]} format.
agent_registry_iam_by_principals = {
  "principalSet://goog/group/agent-platform@example.com" = [
    "roles/iap.egressor"
  ]
}

# A single service registered outside this stage. Set at most one of
# 'agent_id', 'endpoint_id' or 'mcp_server_id' to narrow the binding
# down from the whole registry.
agent_registry_iam_bindings = {
  support-to-partner = {
    members = [
      "principal://agents.global.proj-1234567890.system.id.goog/resources/aiplatform/projects/1234567890/locations/europe-west1/reasoningEngines/support-agent"
    ]
    role     = "roles/iap.egressor"
    agent_id = "partner-agent"
  }
}

# Additive: leaves members granted outside Terraform untouched.
agent_registry_iam_bindings_additive = {
  support-to-legacy-mcp = {
    member        = "principal://agents.global.proj-1234567890.system.id.goog/resources/aiplatform/projects/1234567890/locations/europe-west1/reasoningEngines/support-agent"
    role          = "roles/iap.egressor"
    mcp_server_id = "legacy-mcp"
  }
}
```

> [!NOTE]
> Destinations that are not registered in Agent Registry cannot be targeted by these bindings, since a binding needs a registry resource to attach to. Controlling egress toward unregistered hosts and paths requires the `V2` policy model, which this stage does not support — see [Policy model](#policy-model).

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
| [networking_config](variables.tf#L375) | The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links. | <code title="object&#40;&#123;&#10;  subnet &#61; string&#10;  vpc    &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [project_id](variables.tf#L384) | The id of the project where to create the resources. | <code>string</code> | ✓ |  |
| [agent_gateway_config](variables.tf#L15) | Agent Gateway configuration including authorization extensions. | <code title="object&#40;&#123;&#10;  egress &#61; optional&#40;object&#40;&#123;&#10;    iap &#61; optional&#40;object&#40;&#123;&#10;      fail_open &#61; optional&#40;bool, true&#41;&#10;      iam_enforcement_mode &#61; optional&#40;string&#41;&#10;      policy_version &#61; optional&#40;string, &#34;V1&#34;&#41;&#10;      timeout        &#61; optional&#40;string, &#34;2s&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;    model_armor_config &#61; optional&#40;object&#40;&#123;&#10;      authz_hosts &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;      enable      &#61; optional&#40;bool, false&#41;&#10;      fail_open   &#61; optional&#40;bool, false&#41;&#10;      timeout     &#61; optional&#40;string, &#34;2s&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;    registry_locations &#61; optional&#40;list&#40;string&#41;, &#91;&#34;global&#34;, &#34;regional&#34;&#93;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [agent_registry_iam](variables.tf#L77) | Agent Registry IAM bindings in {ROLE => [MEMBERS]} format. | <code>map&#40;list&#40;string&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [agent_registry_iam_bindings](variables.tf#L84) | Authoritative Agent Registry IAM bindings in {KEY => {role = ROLE, members = [], condition = {}}} format. Set at most one of the '*_id' attributes to scope the binding to a single registry resource, or none to target the whole registry. Keys are arbitrary. | <code title="map&#40;object&#40;&#123;&#10;  members       &#61; list&#40;string&#41;&#10;  role          &#61; string&#10;  agent_id      &#61; optional&#40;string&#41;&#10;  endpoint_id   &#61; optional&#40;string&#41;&#10;  mcp_server_id &#61; optional&#40;string&#41;&#10;  condition &#61; optional&#40;object&#40;&#123;&#10;    expression  &#61; string&#10;    title       &#61; string&#10;    description &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [agent_registry_iam_bindings_additive](variables.tf#L109) | Additive Agent Registry IAM bindings. Set at most one of the '*_id' attributes to scope the binding to a single registry resource, or none to target the whole registry. Keys are arbitrary. | <code title="map&#40;object&#40;&#123;&#10;  member        &#61; string&#10;  role          &#61; string&#10;  agent_id      &#61; optional&#40;string&#41;&#10;  endpoint_id   &#61; optional&#40;string&#41;&#10;  mcp_server_id &#61; optional&#40;string&#41;&#10;  condition &#61; optional&#40;object&#40;&#123;&#10;    expression  &#61; string&#10;    title       &#61; string&#10;    description &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [agent_registry_iam_by_principals](variables.tf#L134) | Authoritative Agent Registry IAM bindings in {PRINCIPAL => [ROLES]} format. Principals need to be statically defined to avoid errors. Merged internally with the 'agent_registry_iam' variable. | <code>map&#40;list&#40;string&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [agent_registry_services](variables.tf#L141) | Custom service endpoints to register in Agent Registry, keyed by service id. | <code title="map&#40;object&#40;&#123;&#10;  url          &#61; string&#10;  content      &#61; optional&#40;string&#41;&#10;  description  &#61; optional&#40;string&#41;&#10;  display_name &#61; optional&#40;string&#41;&#10;  location     &#61; optional&#40;string, &#34;global&#34;&#41;&#10;  protocol     &#61; optional&#40;string, &#34;HTTP_JSON&#34;&#41;&#10;  type         &#61; optional&#40;string, &#34;endpoint&#34;&#41;&#10;  iam          &#61; optional&#40;map&#40;list&#40;string&#41;&#41;, &#123;&#125;&#41;&#10;  iam_bindings &#61; optional&#40;map&#40;object&#40;&#123;&#10;    members &#61; list&#40;string&#41;&#10;    role    &#61; string&#10;    condition &#61; optional&#40;object&#40;&#123;&#10;      expression  &#61; string&#10;      title       &#61; string&#10;      description &#61; optional&#40;string&#41;&#10;    &#125;&#41;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;  iam_bindings_additive &#61; optional&#40;map&#40;object&#40;&#123;&#10;    member &#61; string&#10;    role   &#61; string&#10;    condition &#61; optional&#40;object&#40;&#123;&#10;      expression  &#61; string&#10;      title       &#61; string&#10;      description &#61; optional&#40;string&#41;&#10;    &#125;&#41;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L203) | Whether deletion protection is enabled. | <code>bool</code> |  | <code>true</code> |
| [model_armor_template_config](variables.tf#L210) | The Model Armor configuration for templates and floor settings. | <code title="object&#40;&#123;&#10;  enabled          &#61; optional&#40;bool, true&#41;&#10;  enforcement_type &#61; optional&#40;string, &#34;INSPECT_AND_BLOCK&#34;&#41;&#10;  floor_setting &#61; optional&#40;object&#40;&#123;&#10;    enabled          &#61; optional&#40;bool, false&#41;&#10;    enforcement_type &#61; optional&#40;string, &#34;INSPECT_AND_BLOCK&#34;&#41;&#10;    logging          &#61; optional&#40;bool, true&#41;&#10;    sdp &#61; optional&#40;object&#40;&#123;&#10;      enabled &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;    malicious_uri &#61; optional&#40;object&#40;&#123;&#10;      enabled &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;    pi_and_jailbreak &#61; optional&#40;object&#40;&#123;&#10;      confidence_level &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;      enabled          &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;    rai_filters &#61; optional&#40;object&#40;&#123;&#10;      DANGEROUS         &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;      HARASSMENT        &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;      HATE_SPEECH       &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;      SEXUALLY_EXPLICIT &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  logging &#61; optional&#40;bool, true&#41;&#10;  malicious_uri &#61; optional&#40;object&#40;&#123;&#10;    enabled &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  pi_and_jailbreak &#61; optional&#40;object&#40;&#123;&#10;    confidence_level &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    enabled          &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  rai_filters &#61; optional&#40;object&#40;&#123;&#10;    DANGEROUS         &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    HARASSMENT        &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    HATE_SPEECH       &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;    SEXUALLY_EXPLICIT &#61; optional&#40;string, &#34;HIGH&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  request_template_id  &#61; optional&#40;string, &#34;agw-request-template&#34;&#41;&#10;  response_template_id &#61; optional&#40;string, &#34;agw-response-template&#34;&#41;&#10;  sdp &#61; optional&#40;object&#40;&#123;&#10;    enabled &#61; optional&#40;string, &#34;ENABLED&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [name](variables.tf#L368) | The name of the resources. | <code>string</code> |  | <code>&#34;geap&#34;</code> |
| [region](variables.tf#L390) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [subnet_self_links](variables-fast.tf#L15) | Shared VPCs subnet IDs. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [agent_gateway_ids](outputs.tf#L15) | The Agent Gateway ids. |  |
| [agent_registry_uris](outputs.tf#L22) | The Agent Registry URIs. |  |
<!-- END TFDOC -->
