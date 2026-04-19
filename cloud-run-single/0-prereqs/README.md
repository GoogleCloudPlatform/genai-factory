# Cloud Run - Single / Project Setup

This stage is part of the `Cloud Run - Single` factory.
It is responsible for setting up the Google Cloud project, activating the APIs and granting the roles you need to deploy and manage the resources that enable the AI use case.

It leverages the Cloud Foundation Fabric [`project-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory).

You can refer to the YAML files [host](data/projects/host/host.yaml) and [service](data/projects/service/service-01.yaml) for more details about enabled APIs and roles assigned in the projects.

## Required roles

To execute this stage, you need these roles:

- `roles/resourcemanager.projectCreator` on the organization or folder where you will create the project.
- `roles/billing.user` on the billing account you wish to use.

Alternatively, you can use the more permissive `roles/owner` on the organization or folder.

## Deploy the stage

```shell
cp terraform.tfvars.sample terraform.tfvars

# Replace prefix, billing account and parent.

terraform init
terraform apply
```

You should now see the `providers.tf` and `terraform.auto.tfvars` files in the [1-apps folder](../1-apps/README.md). Enter the [1-apps folder](../1-apps/README.md) to proceed with the deployment.

## Use existing projects

The `project_config` variable allows to configure for different scenarios regarding project creation and management, as described in the [main README](../../README.md).
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [project_config](variables.tf#L46) | The project configuration. | <code title="object&#40;&#123;&#10;  billing_account_id &#61; optional&#40;string&#41;&#10;  parent             &#61; optional&#40;string&#41;&#10;  prefix             &#61; optional&#40;string&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [enable_deletion_protection](variables.tf#L15) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [enable_iac_sa_impersonation](variables.tf#L22) | Whether the user running this module should be granted serviceAccountTokenCreator on the IaC service account. | <code>bool</code> |  | <code>true</code> |
| [networking_config](variables.tf#L28) | The networking configuration. | <code title="object&#40;&#123;&#10;  create &#61; optional&#40;bool, true&#41;&#10;  subnet &#61; optional&#40;object&#40;&#123;&#10;    ip_cidr_range &#61; optional&#40;string, &#34;10.0.0.0&#47;24&#34;&#41;&#10;    name          &#61; optional&#40;string, &#34;sub-0&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  subnet_proxy_only &#61; optional&#40;object&#40;&#123;&#10;    ip_cidr_range &#61; optional&#40;string, &#34;10.20.0.0&#47;24&#34;&#41;&#10;    name          &#61; optional&#40;string, &#34;proxy-only-sub-0&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  vpc_name &#61; optional&#40;string, &#34;net-0&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [region](variables.tf#L63) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [buckets](outputs.tf#L69) | Created buckets. |  |
| [networking_config](outputs.tf#L74) | The networking configuration. |  |
| [projects](outputs.tf#L79) | Created projects. |  |
| [region](outputs.tf#L84) | The region where to create the resources. |  |
| [service_accounts](outputs.tf#L89) | Created service accounts. |  |
<!-- END TFDOC -->
