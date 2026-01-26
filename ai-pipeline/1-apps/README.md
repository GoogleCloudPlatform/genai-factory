# Vertex AI Pipeline / Platform Deployment

This stage is part of the `Vertex AI pipeline factory`.
It is responsible for deploying the components enabling the AI use case, either in the project you created in [0-projects](../0-projects) or in an existing project.

This example demonstrates how to run a Vertex AI Custom Job with PSC Interface to access a private Cloud SQL database.

![Architecture Diagram](../diagram.png)

## Deploy the stage

This assumes you have created a project leveraging the [0-projects](../0-projects) stage.

```shell
cp terraform.tfvars.sample terraform.tfvars # Customize
terraform init
terraform apply

# Follow the commands in the output.
```

## I have not used 0-projects

The [0-projects](../0-projects) stage generates the necessary Terraform input files for this stage. If you're not using the [0-projects stage](../0-projects), you'll need to manually add the required variables to your `terraform.tfvars` file, as defined in [variables.tf](./variables.tf).
<!-- BEGIN TFDOC -->
## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_db_configs"></a> [db\_configs](#input\_db\_configs) | The Cloud SQL configurations. | <pre>object({<br/>    availability_type = optional(string, "REGIONAL")<br/>    database_version  = optional(string, "POSTGRES_14")<br/>    flags             = optional(map(string), { "cloudsql.iam_authentication" = "on" })<br/>    tier              = optional(string, "db-f1-micro")<br/>  })</pre> | `{}` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Whether deletion protection should be enabled. | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the resources. This is also the project suffix if a new project is created. | `string` | `"gf-pipeline-0"` | no |
| <a name="input_networking_config"></a> [networking\_config](#input\_networking\_config) | The networking configuration. | <pre>object({<br/>    create = optional(bool, true)<br/>    vpc_id = optional(string, "net-0")<br/>    subnet = optional(object({<br/>      ip_cidr_range = optional(string, "10.0.0.0/24")<br/>      name          = optional(string, "sub-0")<br/>    }), {})<br/>    subnet_proxy_only = optional(object({<br/>      ip_cidr_range = optional(string, "10.20.0.0/24")<br/>      name          = optional(string, "proxy-only-sub-0")<br/>      purpose       = optional(string, "REGIONAL_MANAGED_PROXY")<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_project_config"></a> [project\_config](#input\_project\_config) | The project where to create the resources. | <pre>object({<br/>    id     = string<br/>    number = string<br/>  })</pre> | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where to create the resources. | `string` | `"europe-west1"` | no |
| <a name="input_service_accounts"></a> [service\_accounts](#input\_service\_accounts) | The pre-created service accounts used by the blueprint. | <pre>map(object({<br/>    email     = string<br/>    iam_email = string<br/>    id        = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_commands"></a> [commands](#output\_commands) | Run the following commands when the deployment completes to deploy the app. |
<!-- END TFDOC -->
