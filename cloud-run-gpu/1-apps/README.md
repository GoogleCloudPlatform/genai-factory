# Cloud Run - GPU / Platform Deployment

This stage is part of the `Cloud Run GPU factory`.
It is responsible for deploying the components enabling the AI use case, either in the project you created in [0-projects](../0-projects) or in an existing project.

![Architecture Diagram](../diagram.png)

## Deploy the stage

This assumes you have created a project leveraging the [0-projects](../0-projects) stage.

```shell
cp terraform.tfvars.sample terraform.tfvars # Customize
terraform init
terraform apply

# Follow the commands in the output.
```

## Query the applications

Once the applications have been deployed you can use the gcloud command in the terraform output to create an authentication proxy and test your application.

## I have not used 0-projects

The [0-projects](../0-projects) stage generates the necessary Terraform input files for this stage. If you're not using the [0-projects stage](../0-projects), you'll need to manually add the required variables to your `terraform.tfvars` file, as defined in [variables.tf](./variables.tf).

<!-- BEGIN TFDOC -->
## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [project_config](variables.tf#L88) | The project where to create the resources. | <code title="object&#40;&#123;&#10;  id     &#61; string&#10;  number &#61; string&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> | ✓ |  |
| [cloud_run_configs](variables.tf#L20) | The Cloud Run configurations. | <code title="object&#40;&#123;&#10;  containers &#61; optional&#40;map&#40;any&#41;, &#123;&#10;    gemma &#61; &#123;&#10;      image &#61; &#34;us-docker.pkg.dev&#47;cloudrun&#47;container&#47;gemma&#47;gemma3-1b:latest&#34;&#10;      env &#61; &#123;&#10;        OLLAMA_NUM_PARALLEL &#61; &#34;4&#34;&#10;        PORT                &#61; 8081&#10;      &#125;&#10;      ports &#61; &#123;&#125;&#10;      resources &#61; &#123;&#10;        limits &#61; &#123;&#10;          cpu              &#61; &#34;4&#34;&#10;          memory           &#61; &#34;16Gi&#34;&#10;          &#34;nvidia.com&#47;gpu&#34; &#61; &#34;1&#34;&#10;        &#125;&#10;      &#125;&#10;    &#125;&#10;    chat-ui &#61; &#123;&#10;      image &#61; &#34;us-docker.pkg.dev&#47;google-samples&#47;containers&#47;gke&#47;gradio-app:v1.0.4&#34;&#10;      ports &#61; &#123;&#10;        default &#61; &#123;&#10;          container_port &#61; 7860&#10;        &#125;&#10;      &#125;&#10;      env &#61; &#123;&#10;        CONTEXT_PATH &#61; &#34;&#47;v1&#47;chat&#47;completions&#34;&#10;        HOST         &#61; &#34;http:&#47;&#47;localhost:8081&#34;&#10;        LLM_ENGINE   &#61; &#34;openai-chat&#34;&#10;        MODEL_ID     &#61; &#34;gemma3:1b&#34;&#10;      &#125;&#10;      resources &#61; &#123;&#10;        limits &#61; &#123;&#10;          cpu    &#61; &#34;500m&#34;&#10;          memory &#61; &#34;256Mi&#34;&#10;        &#125;&#10;      &#125;&#10;    &#125;&#10;  &#125;&#41;&#10;  ingress                       &#61; optional&#40;string, &#34;INGRESS_TRAFFIC_ALL&#34;&#41;&#10;  max_instance_count            &#61; optional&#40;number, 3&#41;&#10;  service_invokers              &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  vpc_access_egress             &#61; optional&#40;string, &#34;ALL_TRAFFIC&#34;&#41;&#10;  vpc_access_tags               &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  gpu_zonal_redundancy_disabled &#61; optional&#40;bool, true&#41;&#10;  node_selector &#61; optional&#40;map&#40;string&#41;, &#123;&#10;    accelerator &#61; &#34;nvidia-l4&#34;&#10;  &#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [enable_deletion_protection](variables.tf#L74) | Whether deletion protection should be enabled. | <code>bool</code> |  | <code>true</code> |
| [name](variables.tf#L81) | The name of the resources. This is also the project suffix if a new project is created. | <code>string</code> |  | <code>&#34;gf-rgpu-0&#34;</code> |
| [region](variables.tf#L97) | The GCP region where to deploy the resources. | <code>string</code> |  | <code>&#34;europe-west1&#34;</code> |
| [service_accounts](variables.tf#L104) | The pre-created service accounts used by the blueprint. | <code title="map&#40;object&#40;&#123;&#10;  email     &#61; string&#10;  iam_email &#61; string&#10;  id        &#61; string&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [commands](outputs.tf#L15) | Run the following commands when the deployment completes to deploy the app. |  |
<!-- END TFDOC -->
