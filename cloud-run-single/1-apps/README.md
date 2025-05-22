# Cloud Run - single / Platform
<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [project_id](variables.tf#L72) | The project if where to create the resources. | <code>string</code> | ✓ |  |
| [allowed_ip_ranges](variables.tf#L15) | The ip ranges that can call the Cloud Run service. | <code>list&#40;string&#41;</code> |  | <code>&#91;&#34;0.0.0.0&#47;0&#34;&#93;</code> |
| [cloud_run_configs](variables.tf#L22) | The Cloud Run configurations. | <code title="object&#40;&#123;&#10;  containers &#61; optional&#40;map&#40;any&#41;, &#123;&#10;    ai &#61; &#123;&#10;      image &#61; &#34;us-docker.pkg.dev&#47;cloudrun&#47;container&#47;hello&#34;&#10;    &#125;&#10;  &#125;&#41;&#10;  ingress            &#61; optional&#40;string, &#34;INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER&#34;&#41;&#10;  max_instance_count &#61; optional&#40;number, 3&#41;&#10;  service_invokers   &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  vpc_access_egress  &#61; optional&#40;string, &#34;ALL_TRAFFIC&#34;&#41;&#10;  vpc_access_tags    &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L40) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [expose_external](variables.tf#L40) | Whether to expose function externally or not. | <code>bool</code> |  | <code>true</code> |
| [expose_internal](variables.tf#L40) | Whether to expose function internally or not. | <code>bool</code> |  | <code>true</code> |
| [ip_address](variables.tf#L47) | The optional load balancer IP address. If not specified, the module will create one. | <code>string</code> |  | <code>null</code> |
| [name](variables.tf#L53) | The name of the resources. This is also the project suffix if a new project is created. | <code>string</code> |  | <code>&#34;gf-srun-0&#34;</code> |
| [networking_config](variables.tf#L60) | The networking configuration. | <code title="object&#40;&#123;&#10;   vpc_id      &#61; string create      &#61; optional&#40;bool, true&#41;&#10;  subnet_cidr &#61; optional&#40;string, &#34;10.0.0.0&#47;24&#34;&#41;&#10;  subnet_id   &#61; optional&#40;string, &#34;sub-0&#34;&#41;&#10;  vpc_id      &#61; optional&#40;string, &#34;net-0&#34;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [public_domains](variables.tf#L78) | The list of domains connected to the public load balancer. | <code>list&#40;string&#41;</code> |  | <code>&#91;&#34;example.com&#34;&#93;</code> |
| [private_domains](variables.tf#L78) | The list of domains connected to the internal load balancer. | <code>list&#40;string&#41;</code> |  | <code>&#91;&#34;example.com&#34;&#93;</code> |
| [private_root_domain](variables.tf#L78) | The root domain for internal DNS signature. | <code>string</code> |  | <code>&#91;&#34;internal.example.com&#34;&#93;</code> |
| [region](variables.tf#L85) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [service_accounts](variables.tf#L92) | The pre-created service accounts used by the blueprint. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [commands](outputs.tf#L15) | Run the following commands when the deployment completes to deploy the app. |  |
| [external_ip_address](outputs.tf#L32) | The External load balancer IP address. |  |
| [internal_ip_address](outputs.tf#L32) | The Internal load balancer IP address. |  |
<!-- END TFDOC -->