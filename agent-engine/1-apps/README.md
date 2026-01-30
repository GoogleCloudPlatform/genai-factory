# Agent Engine / Agent Deployment

This stage is part of `Agent Engine` factory.
It is responsible for deploying agent engine and other useful infrastructure resources inside the project you created in [0-projects](../0-projects) or in an existing project.

## Deploy the stage

This assumes you have created a project by leveraging the [0-projects](../0-projects) stage.

```shell
cp terraform.tfvars.sample terraform.tfvars # Customize if needed
terraform init
terraform apply

# Follow the commands in the output.
```

## Interact with the Agent

Once you deployed, use the commands output by Terraform to update and test your agent.

## I have not used 0-projects

The [0-projects](../0-projects) stage generates the necessary Terraform input files for this stage. If you're not using the [0-projects stage](../0-projects), you'll need to manually add the required variables to your `terraform.tfvars` file, as defined in [variables.tf](./variables.tf).
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [prefix](variables.tf#L64) | The unique name prefix to be used for all global unique resources. | <code>string</code> | ✓ |  |
| [project_config](variables.tf#L70) | The project where to create the resources. | <code title="object&#40;&#123;&#10;  id     &#61; string&#10;  number &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [agent_engine_config](variables.tf#L15) |  | <code title="object&#40;&#123;&#10;  agent_framework        &#61; optional&#40;string, &#34;google-adk&#34;&#41;&#10;  class_methods          &#61; optional&#40;list&#40;any&#41;, &#91;&#93;&#41;&#10;  enable_adk_telemetry   &#61; optional&#40;bool, true&#41;&#10;  enable_adk_msg_capture &#61; optional&#40;bool, true&#41;&#10;  enable_psc_i           &#61; optional&#40;bool, true&#41;&#10;  max_instances          &#61; optional&#40;number, 5&#41;&#10;  min_instances          &#61; optional&#40;number, 1&#41;&#10;  python_version         &#61; optional&#40;string, &#34;3.13&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L29) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [name](variables.tf#L36) | The name of the agent. | <code>string</code> |  | <code>&#34;agent-0&#34;</code> |
| [networking_config](variables.tf#L43) | The networking configuration. | <code title="object&#40;&#123;&#10;  create                &#61; optional&#40;bool, true&#41;&#10;  network_attachment_id &#61; optional&#40;string&#41;&#10;  proxy_ip              &#61; optional&#40;string, &#34;10.0.0.100&#34;&#41;&#10;  proxy_port            &#61; optional&#40;string, &#34;443&#34;&#41;&#10;  vpc_id                &#61; optional&#40;string, &#34;net-0&#34;&#41;&#10;  subnet &#61; optional&#40;object&#40;&#123;&#10;    ip_cidr_range &#61; optional&#40;string, &#34;10.0.0.0&#47;24&#34;&#41;&#10;    name          &#61; optional&#40;string, &#34;sub-0&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  subnet_proxy_only &#61; optional&#40;object&#40;&#123;&#10;    ip_cidr_range &#61; optional&#40;string, &#34;10.20.0.0&#47;24&#34;&#41;&#10;    name          &#61; optional&#40;string, &#34;proxy-only-sub-0&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [region](variables.tf#L79) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [service_accounts](variables.tf#L86) | The pre-created service accounts used by the blueprint. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [source_config](variables.tf#L96) | The source file configurations. | <code title="object&#40;&#123;&#10;  entrypoint_module &#61; optional&#40;string, &#34;agent&#34;&#41;&#10;  entrypoint_object &#61; optional&#40;string, &#34;agent&#34;&#41;&#10;  requirements_path &#61; optional&#40;string, &#34;requirements.txt&#34;&#41;&#10;  tar_gz_file_name &#61; optional&#40;string, &#34;source.tar.gz&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [agent_id](outputs.tf#L15) | The agent engine agent id. |  |
| [commands](outputs.tf#L20) | Run the following commands when the deployment finalize the setup, deploy and test your agent. |  |
<!-- END TFDOC -->
