# Cloud Run - Single / Project Setup

This stage is part of the `Vertex AI pipeline factory`.
It is responsible for setting up the Google Cloud project, activating the APIs and granting the roles you need to deploy and manage the components enabling the AI use case.

It leverages the Cloud Foundation Fabric [`project-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory).

You can refer to the [YAML project configuration](data/project.yaml) for more details about enabled APIs and roles assigned in the project.

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

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Whether deletion protection should be enabled. | `bool` | `true` | no |
| <a name="input_enable_iac_sa_impersonation"></a> [enable\_iac\_sa\_impersonation](#input\_enable\_iac\_sa\_impersonation) | Whether the user running this module should be granted serviceAccountTokenCreator on the automation service account. | `bool` | `true` | no |
| <a name="input_project_config"></a> [project\_config](#input\_project\_config) | The project configuration. | <pre>object({<br/>    billing_account_id = optional(string)<br/>    parent             = optional(string)<br/>    prefix             = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where to create the buckets. | `string` | `"europe-west1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_buckets"></a> [buckets](#output\_buckets) | Created buckets. |
| <a name="output_projects"></a> [projects](#output\_projects) | Created projects. |
| <a name="output_service_accounts"></a> [service\_accounts](#output\_service\_accounts) | Created service accounts. |
<!-- END TFDOC -->
