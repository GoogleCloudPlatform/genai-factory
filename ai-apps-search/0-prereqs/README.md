# AI Applications - Search / Prerequisites stage

This stage is part of the `AI Applications - Search factory`.

It is responsible for setting up the Google Cloud project, activating the APIs and granting the roles you need to deploy and manage the components enabling the AI use case.

It performs the following tasks:

- Sets up GCP projects.
- Activates the required APIs.
- Creates service accounts.
- Grants required roles to identities (users, service agents, and service accounts).

This stage leverages the Cloud Foundation Fabric [project-factory module](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory).

The [project](data/projects/service-01.yaml) YAML file contains the definition of these resources.

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
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [prefix](variables.tf#L28) | The name prefix to use for resources with a globally unique name. | <code>string</code> | ✓ |  |
| [project_config](variables.tf#L34) | The project configuration. | <code title="object&#40;&#123;&#10;  billing_account_id &#61; optional&#40;string&#41;&#10;  parent             &#61; optional&#40;string&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [enable_deletion_protection](variables.tf#L15) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [enable_iac_sa_impersonation](variables.tf#L22) | Whether the user running this module should be granted serviceAccountTokenCreator on the automation service account. | <code>bool</code> |  | <code>true</code> |
| [region](variables.tf#L50) | The GCP region. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [buckets](outputs.tf#L46) | Created buckets. |  |
| [projects](outputs.tf#L51) | Created projects. |  |
| [service_accounts](outputs.tf#L56) | Created service accounts. |  |
<!-- END TFDOC -->
