# Agent Platform / Platform and Gateway Deployment

This stage is part of the `Gemini Enterprise Agent Platform` factory.

It is responsible for deploying the components enabling the Agent Platform architecture inside the service project created in [0-prereqs](../0-prereqs/README.md) or in an existing project.

It performs the following tasks:

- Creates a Private Service Connect (PSC) Network Attachment in the service project pointing to the Shared VPC subnet.
- Deploys the Egress Agent Gateway configured with `AGENT_TO_ANYWHERE` access path.
- Configures dynamic authorization extensions and policies:
  - **Model Armor** (`CONTENT_AUTHZ`): Inspects and sanitizes LLM prompt requests and model responses using configured Model Armor templates.
  - **Identity-Aware Proxy (IAP)** (`REQUEST_AUTHZ`): Enforces identity verification and access control on incoming requests.
- Registers service endpoints in **Agent Registry**:
  - Automatically registers Google APIs (Vertex AI, Dialogflow, Discovery Engine, Model Armor, Cloud Logging, Cloud Monitoring) across multiple endpoint variants (global, mTLS, regional, regional mTLS, and Regional Endpoint Protocol / REP).
  - Registers custom HTTP/gRPC endpoints defined in `var.custom_services` with JSONRPC protocol binding.

## Deploy the stage

If you created your project(s) through [0-prereqs](../0-prereqs/README.md), you should already see a `providers.tf` and a `terraform.auto.tfvars` file in this folder.

```shell
terraform init
terraform apply
```

## Authorization Policies

The stage dynamically loads and creates authorization extensions and policies from YAML files located in the `policies/` directory:

- [`policies/model_armor.yaml`](./policies/model_armor.yaml): Configures Model Armor content authorization on the Agent Gateway. Can be toggled with `var.enable_model_armor`.
- [`policies/iap.yaml`](./policies/iap.yaml): Configures Identity-Aware Proxy (IAP) request authorization on the Agent Gateway.

To pass custom Model Armor templates, customize your `terraform.tfvars`:

```hcl
enable_model_armor               = true
model_armor_request_template_id  = "projects/my-project/locations/europe-west1/templates/my-req-template"
model_armor_response_template_id = "projects/my-project/locations/europe-west1/templates/my-resp-template"
model_armor_authz_hosts          = ["aiplatform.googleapis.com", "europe-west1-aiplatform.googleapis.com"]
```

## Registering Custom Services

You can register your own tools or backend services in Agent Registry by setting the `custom_services` variable:

```hcl
custom_services = [
  {
    id           = "weather-service"
    display_name = "Weather API Service"
    url          = "https://weather.example.com"
    description  = "Internal weather forecast service"
  }
]
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
| [networking_config](variables.tf#L70) | The networking configuration. Each element is either the id of the resource or the key of the map var.vpc_self_links. | <code title="object&#40;&#123;&#10;  subnet &#61; string&#10;  vpc    &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [project_id](variables.tf#L79) | The id of the project where to create the resources. | <code>string</code> | ✓ |  |
| [custom_services](variables.tf#L14) | List of custom (non-Google) service endpoints to register in Agent Registry. | <code title="list&#40;object&#40;&#123;&#10;  id           &#61; string&#10;  display_name &#61; string&#10;  url          &#61; string&#10;  description  &#61; optional&#40;string&#41;&#10;&#125;&#41;&#41;">list&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#91;&#93;</code> |
| [enable_model_armor](variables.tf#L25) | When true, also create the Model Armor CONTENT_AUTHZ extension and policy. Requires both model_armor_request_template_id and model_armor_response_template_id. | <code>bool</code> |  | <code>false</code> |
| [google_apis](variables.tf#L31) | Map of Google API IDs to display names to register in Agent Registry. | <code>map&#40;string&#41;</code> |  | <code title="&#123;&#10;  &#34;dialogflow&#34;      &#61; &#34;Dialogflow API&#34;&#10;  &#34;discoveryengine&#34; &#61; &#34;Discovery Engine API&#34;&#10;  &#34;modelarmor&#34;      &#61; &#34;Model Armor API&#34;&#10;  &#34;storage&#34;         &#61; &#34;Cloud Storage API&#34;&#10;  &#34;aiplatform&#34;      &#61; &#34;Vertex AI API&#34;&#10;  &#34;logging&#34;         &#61; &#34;Cloud Logging API&#34;&#10;  &#34;monitoring&#34;      &#61; &#34;Cloud Monitoring API&#34;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [model_armor_authz_hosts](variables.tf#L45) | Optional list of Host header values to scope the Model Armor CONTENT_AUTHZ policy to. | <code>list&#40;string&#41;</code> |  | <code>&#91;&#93;</code> |
| [model_armor_request_template_id](variables.tf#L51) | Model Armor request-side template ID (regional, in this project + region). Required when enable_model_armor = true. | <code>string</code> |  | <code>null</code> |
| [model_armor_response_template_id](variables.tf#L57) | Model Armor response-side template ID (regional, in this project + region). Required when enable_model_armor = true. | <code>string</code> |  | <code>null</code> |
| [name](variables.tf#L63) | The name of the resources. | <code>string</code> |  | <code>&#34;agw-geap&#34;</code> |
| [region](variables.tf#L85) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [authz_extension_ids](outputs.tf#L16) | Map of policy name to authorization service extension ID. |  |
| [authz_policy_ids](outputs.tf#L21) | Map of policy name to authorization policy ID. |  |
| [service_extensions_sa](outputs.tf#L26) | The Agent Gateway service extensions service account for Model Armor. |  |
<!-- END TFDOC -->
