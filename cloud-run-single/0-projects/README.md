# Cloud Run - single / Project Setup

This module is part of the Single Cloud Run factory and is responsible for setting up the necessary Google Cloud project and permissions required for deploying the application.

It leverages the following Cloud Foundation Fabric  [`project-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory) for creating and configuring Google Cloud projects, enabling APIs, and managing IAM policies.

The primary goal of this module is to automate the initial setup phase for the Cloud Run application deployment. This includes optionally creating a new Google Cloud project, configuring billing, enabling required APIs, creating dedicated service accounts with minimal necessary permissions, and setting up the Terraform state bucket and backend configuration for the subsequent `1-apps` module.

## Deployed Architecture

This module deploys the following core components:

- **Google Cloud Project:** Creates or configures a Google Cloud project based on the provided configuration.
- **Service Accounts:** Creates dedicated service accounts with fine-grained IAM roles required by the application and the Terraform deployment itself.
- **Terraform State Backend:** Sets up a GCS bucket to store the Terraform state for the `1-apps` module and grants the necessary permissions to the Terraform service account.

You can refer to the [YAML project configuration](data/project.yaml) for more details about enabled APIs and roles assigned on the project.

## Configurations

The behavior of this module is controlled by the `project_config` variable. This variable allows for different scenarios regarding project creation and management:

- **Default: Create and Manage New Projects:**
  If `project_config.create` is `true` (default) and `project_config.control` is `true` (default), the module will create a new project, link it to the specified billing account, and manage its configuration (APIs, service accounts, IAM). The project name will be derived from the `prefix` and `name` variables.

- **Control Existing Projects:**
  If `project_config.create` is `false` and `project_config.control` is `true`, the module will not create a new project but will configure an existing one. You must provide the existing project ID by setting the `name` field in the [YAML file](data/project.yaml) (making sure that the prefix+name configuration matches with the existing project ID) and ensure the principal running Terraform has permissions to manage resources within that project. The module will then enable necessary APIs, create service accounts, and set IAM roles in the specified existing project.

- **Create and Control Projects Outside genai-factory:**
  If `project_config.create` is `false` and `project_config.control` is `false`, the module will neither create nor configure a project. It assumes the project and necessary permissions are managed entirely outside of this module. In this scenario, you are responsible for ensuring the target project exists and has all the required APIs enabled and service accounts/roles created as expected by the `1-apps` module. You will need to manually configure the `terraform.tfvars` for the `1-apps` module with the details of your existing project and service accounts.

<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [project_config](variables.tf#L15) | The project configuration. | <code title="object&#40;&#123;&#10;  billing_account_id &#61; optional&#40;string&#41;     &#35; if create or control equals true&#10;  control            &#61; optional&#40;bool, true&#41; &#35; to control an existing project&#10;  create             &#61; optional&#40;bool, true&#41; &#35; to create the project&#10;  parent             &#61; optional&#40;string&#41;     &#35; if control equals true&#10;  prefix             &#61; optional&#40;string&#41;     &#35; the prefix of the project name&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [region](variables.tf#L34) | The region where to create service accounts and buckets. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [buckets](outputs.tf#L48) | Created buckets. |  |
| [projects](outputs.tf#L53) | Created projects. |  |
| [service_accounts](outputs.tf#L58) | Created service accounts. |  |
<!-- END TFDOC -->
