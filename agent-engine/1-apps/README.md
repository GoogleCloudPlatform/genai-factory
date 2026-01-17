# Agent Engine / App Deployment

This stage is part of `Agent Engine` factory.
It is responsible for deploying the agent inside the project you created in [0-projects](../0-projects) or in an existing project.

## Deploy the stage

This assumes you have created a project by leveraging the [0-projects](../0-projects) stage.

```shell
cp terraform.tfvars.sample terraform.tfvars # Customize if needed
terraform init
terraform apply

# Follow the commands in the output.
```

## Interact with the Agent

Once deployed, use the curl commands output by Terraform to test, update, or enable PSC-I for the agent.

## I have not used 0-projects

The [0-projects](../0-projects) stage generates the necessary Terraform input files for this stage. If you're not using the [0-projects stage](../0-projects), you'll need to manually add the required variables to your `terraform.tfvars` file, as defined in [variables.tf](./variables.tf).
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [project_config](variables.tf#L34) | The project where to create the resources. | <code title="object&#40;&#123;&#10;  id     &#61; string&#10;  number &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [bucket_config](variables.tf#L15) | The GCS bucket configuration. | <code title="object&#40;&#123;&#10;  create                      &#61; optional&#40;bool, true&#41;&#10;  deletion_protection         &#61; optional&#40;bool, true&#41;&#10;  name                        &#61; optional&#40;string&#41;&#10;  uniform_bucket_level_access &#61; optional&#40;bool, true&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [name](variables.tf#L27) | The name of the agent. | <code>string</code> |  | <code>&#34;agent-0&#34;</code> |
| [region](variables.tf#L43) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [service_accounts](variables.tf#L50) | The pre-created service accounts used by the blueprint. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [agent_id](outputs.tf#L15) | The Agent Engine ID. |  |
| [agent_object](outputs.tf#L20) | The Agent Engine object. |  |
| [curl_enable_psci](outputs.tf#L35) | Curl command to enable PSC-I. |  |
| [curl_test_agent](outputs.tf#L25) | Curl command to test the agent. |  |
| [curl_update_agent](outputs.tf#L30) | Curl command to update the agent. |  |
<!-- END TFDOC -->
