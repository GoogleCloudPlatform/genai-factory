# Cloud Run - RAG / Platform Deployment

This module is part of the `Cloud Run RAG factory`.
It is responsible for deploying the components enabling the AI use case, either in the project you created in [0-projects](../0-projects) or in an existing project.

![Architecture Diagram](../diagram.png)

## Deploy the module

This assumes you have created a project leveraging the [0-projects](../0-projects) module.

```shell
cp terraform.tfvars.sample terraform.tfvars # Customize
terraform init
terraform apply

# Follow the commands in the output.
```

## I have not used 0-projects

The [0-projects](../0-projects) module also produces the Terraform input files needed for this stage to work. If you are not leveraging [0-projects](../0-projects) it's your responsibility to create the `terraform.tfvars` file, reflecting what's requested by [variables.tf](./variables.tf) in this module.

<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [project_config](variables.tf#L149) | The project where to create the resources. | <code title="object&#40;&#123;&#10;  id     &#61; string&#10;  number &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [ca_pool_name_suffix](variables.tf#L18) | The name suffix of the CA pool used for app ILB certificates. | <code>string</code> |  | <code>&#34;ca-pool-0&#34;</code> |
| [cloud_run_configs](variables.tf#L25) | The Cloud Run configurations. | <code title="object&#40;&#123;&#10;  frontend &#61; object&#40;&#123;&#10;    containers &#61; optional&#40;map&#40;any&#41;, &#123;&#10;      frontend &#61; &#123;&#10;        image &#61; &#34;us-docker.pkg.dev&#47;cloudrun&#47;container&#47;hello&#34;&#10;        ports &#61; &#123;&#10;          frontend &#61; &#123;&#10;            container_port &#61; 8080&#10;          &#125;&#10;        &#125;&#10;      &#125;&#10;    &#125;&#41;&#10;    deletion_protection &#61; optional&#40;bool, true&#41;&#10;    ingress             &#61; optional&#40;string, &#34;INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER&#34;&#41;&#10;    max_instance_count  &#61; optional&#40;number, 3&#41;&#10;    service_invokers    &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;    vpc_access_egress   &#61; optional&#40;string, &#34;ALL_TRAFFIC&#34;&#41;&#10;    vpc_access_tags     &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  &#125;&#41;&#10;  ingestion &#61; object&#40;&#123;&#10;    containers &#61; optional&#40;map&#40;any&#41;, &#123;&#10;      ingestion &#61; &#123;&#10;        image &#61; &#34;us-docker.pkg.dev&#47;cloudrun&#47;container&#47;hello&#34;&#10;      &#125;&#10;    &#125;&#41;&#10;    deletion_protection &#61; optional&#40;bool, true&#41;&#10;    ingress             &#61; optional&#40;string, &#34;INGRESS_TRAFFIC_INTERNAL_ONLY&#34;&#41;&#10;    max_instance_count  &#61; optional&#40;number, 3&#41;&#10;    service_invokers    &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;    vpc_access_egress   &#61; optional&#40;string, &#34;ALL_TRAFFIC&#34;&#41;&#10;    vpc_access_tags     &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  &#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code title="&#123;&#10;  frontend  &#61; &#123;&#125;&#10;  ingestion &#61; &#123;&#125;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [db_configs](variables.tf#L67) | The Cloud SQL configurations. | <code title="object&#40;&#123;&#10;  availability_type &#61; optional&#40;string, &#34;REGIONAL&#34;&#41;&#10;  database_version  &#61; optional&#40;string, &#34;POSTGRES_14&#34;&#41;&#10;  flags             &#61; optional&#40;map&#40;string&#41;, &#123; &#34;cloudsql.iam_authentication&#34; &#61; &#34;on&#34; &#125;&#41;&#10;  tier              &#61; optional&#40;string, &#34;db-f1-micro&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L79) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [ingestion_schedule_configs](variables.tf#L86) | The configuration of the Cloud Scheduler that calls invokes the Cloud Run ingestion job. | <code title="object&#40;&#123;&#10;  attempt_deadline &#61; optional&#40;string, &#34;60s&#34;&#41;&#10;  retry_count      &#61; optional&#40;number, 3&#41;&#10;  schedule         &#61; optional&#40;string, &#34;&#42;&#47;30 &#42; &#42; &#42; &#42;&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [lbs_config](variables.tf#L97) | The load balancers configuration. | <code title="object&#40;&#123;&#10;  external &#61; optional&#40;object&#40;&#123;&#10;    enable &#61; optional&#40;bool, true&#41;&#10;    ip_address        &#61; optional&#40;string&#41;&#10;    domain            &#61; optional&#40;string, &#34;example.com&#34;&#41;&#10;    allowed_ip_ranges &#61; optional&#40;list&#40;string&#41;, &#91;&#34;0.0.0.0&#47;0&#34;&#93;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  internal &#61; optional&#40;object&#40;&#123;&#10;    enable &#61; optional&#40;bool, false&#41;&#10;    ip_address        &#61; optional&#40;string&#41;&#10;    domain            &#61; optional&#40;string, &#34;example.com&#34;&#41;&#10;    allowed_ip_ranges &#61; optional&#40;list&#40;string&#41;, &#91;&#34;0.0.0.0&#47;0&#34;&#93;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code title="&#123;&#10;  external &#61; &#123;&#125;&#10;  internal &#61; &#123;&#125;&#10;&#125;">&#123;&#8230;&#125;</code> |
| [name](variables.tf#L124) | The name of the resources. This is also the project suffix if a new project is created. | <code>string</code> |  | <code>&#34;gf-rrag-0&#34;</code> |
| [networking_config](variables.tf#L131) | The networking configuration. | <code title="object&#40;&#123;&#10;  create &#61; optional&#40;bool, true&#41;&#10;  vpc_id &#61; optional&#40;string, &#34;net-0&#34;&#41;&#10;  subnet &#61; optional&#40;object&#40;&#123;&#10;    ip_cidr_range &#61; optional&#40;string, &#34;10.0.0.0&#47;24&#34;&#41;&#10;    name          &#61; optional&#40;string, &#34;sub-0&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;  subnet_proxy_only &#61; optional&#40;object&#40;&#123;&#10;    ip_cidr_range &#61; optional&#40;string, &#34;10.20.0.0&#47;24&#34;&#41;&#10;    name          &#61; optional&#40;string, &#34;proxy-only-sub-0&#34;&#41;&#10;  &#125;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [region](variables.tf#L158) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [service_accounts](variables.tf#L165) | The pre-created service accounts used by the blueprint. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [commands](outputs.tf#L46) | Run the following commands when the deployment completes to deploy the app. |  |
| [ip_addresses](outputs.tf#L106) | The load balancers IP addresses. |  |
<!-- END TFDOC -->
