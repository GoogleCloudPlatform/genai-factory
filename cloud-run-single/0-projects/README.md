# Cloud Run - single / Project Setup

This module is part of the Single Cloud Run factory and is responsible for setting up the necessary Google Cloud project and permissions required for deploying the application.

It leverages the Cloud Foundation Fabric [`project-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory) module for creating and configuring Google Cloud projects, service accounts and storage buckets for Terraform automation, enabling APIs, and managing IAM policies.

You can refer to the [YAML project configuration](data/project.yaml) for more details about enabled APIs and roles assigned on the project.

## Configurations

The behavior of this module is controlled by the `project_config` variable. This variable allows for different scenarios regarding project creation and management, as described in the [main README](../../README.md).

<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [project_config](variables.tf#L21) | The project configuration. | <code title="object&#40;&#123;&#10;  billing_account_id &#61; optional&#40;string&#41;     &#35; if create or control equal true&#10;  control            &#61; optional&#40;bool, true&#41; &#35; to control an existing project&#10;  create             &#61; optional&#40;bool, true&#41; &#35; to create the project&#10;  parent             &#61; optional&#40;string&#41;     &#35; if control equals true&#10;  prefix             &#61; optional&#40;string&#41;     &#35; the prefix of the project name&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [enable_iac_sa_impersonation](variables.tf#L15) | Whether the user running this module should be granted serviceAccountTokenCreator on the automation service account. | <code>bool</code> |  | <code>true</code> |
| [region](variables.tf#L40) | The region where to create service accounts and buckets. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [buckets](outputs.tf#L48) | Created buckets. |  |
| [projects](outputs.tf#L53) | Created projects. |  |
| [service_accounts](outputs.tf#L58) | Created service accounts. |  |
<!-- END TFDOC -->
