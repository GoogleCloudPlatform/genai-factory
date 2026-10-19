# GenAI Factory

## Audience

This document provides foundational instructions, context, and conventions intended for AI coding agents operating within this repository.

Genai-factory is a collection of **end-to-end blueprints to deploy generative AI infrastructures** in GCP, following security best-practices.

- Embraces IaC best practices. Infrastructure is implemented in [Terraform](https://developer.hashicorp.com/terraform), leveraging [Terraform resources](https://registry.terraform.io/providers/hashicorp/google/latest/docs) and [Cloud Foundations Fabric modules](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric).
- Follows the least-privilege principle: no default service accounts, primitive roles, minimal permissions.
- Compatible with [Cloud Foundation Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast) [project-factory](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory) and application templates.

## Factories Structure

The repository is composed of multiple factories.
Each factory is a folder. The only folders that are not factories are `.github`, `tests`, `tools`.

### Factory Index

Each factory has a dedicated `AGENTS.md` file in its root directory containing factory-specific architecture, key files, test inventories, and implementation learnings. Always read the corresponding factory's `AGENTS.md` before modifying a factory:

| Factory | Agent Instructions | Summary |
| :--- | :--- | :--- |
| `agent-runtime` | [`agent-runtime/AGENTS.md`](./agent-runtime/AGENTS.md) | Vertex AI Agent Engine runtime (ADK & A2A agents), PSC-I networking, Firestore session/task store, Model Armor, and IAM v3 UAP integration. |
| `ai-apps-search` | [`ai-apps-search/AGENTS.md`](./ai-apps-search/AGENTS.md) | Vertex AI Search (Discovery Engine) unstructured document search app backed by GCS. |
| `cloud-run-nl2sql-bq` | [`cloud-run-nl2sql-bq/AGENTS.md`](./cloud-run-nl2sql-bq/AGENTS.md) | Cloud Run NL2SQL ADK agent querying BigQuery behind an external or internal Application Load Balancer. |
| `cloud-run-rag-alloydb` | [`cloud-run-rag-alloydb/AGENTS.md`](./cloud-run-rag-alloydb/AGENTS.md) | Cloud Run RAG frontend and ingestion job using AlloyDB (`pgvector` + `scann` index) and BigQuery. |
| `cloud-run-rag-cloudsql` | [`cloud-run-rag-cloudsql/AGENTS.md`](./cloud-run-rag-cloudsql/AGENTS.md) | Cloud Run RAG frontend and ingestion job using Cloud SQL for PostgreSQL (`pgvector`) and BigQuery. |
| `cloud-run-rag-search` | [`cloud-run-rag-search/AGENTS.md`](./cloud-run-rag-search/AGENTS.md) | Cloud Run RAG frontend and ingestion job using Vertex AI Vector Search 2.0 (Collections, auto-embeddings, Hybrid Search / RRF) and GCS. |
| `cloud-run-single` | [`cloud-run-single/AGENTS.md`](./cloud-run-single/AGENTS.md) | Single Cloud Run GenAI application (`chat`, `adk`, `adk-a2a`, `gemma`, `mcp-server`) with Load Balancer, Cloud Armor, and Model Armor. |
| `ge-agent-platform` | [`ge-agent-platform/AGENTS.md`](./ge-agent-platform/AGENTS.md) | Gemini Enterprise & Agent Platform (Discovery Engine Search/Assistant, native & 3rd-party SaaS data connectors, location-level IdP/ACL config, Agent Registry, custom MCP servers, Model Armor, and IAM v3 UAPs). |
| `gecx-agent-studio` | [`gecx-agent-studio/AGENTS.md`](./gecx-agent-studio/AGENTS.md) | Gemini Enterprise for Customer Experience (CX Agent Studio) with GCS data store and private Cloud Run OpenAPI toolset via Service Directory & Internal TCP Proxy LB. |
| `gecx-dialogflow` | [`gecx-dialogflow/AGENTS.md`](./gecx-dialogflow/AGENTS.md) | Dialogflow CX Conversational Agent with FAQ/unstructured data stores and private Cloud Run Function webhook via Service Directory & Internal TCP Proxy LB. |
| `serve-private-models` | [`serve-private-models/AGENTS.md`](./serve-private-models/AGENTS.md) | Vertex AI Model Garden open models (e.g., Gemma 3) privately exposed via Private Service Connect (PSC) to a Cloud Run application with Load Balancer, Cloud Armor, and Model Armor. |

### Creating a New Factory

When scaffolding a new factory, adhere to these rules:

- **Naming:** The factory folder name should describe the use case (e.g., `cloud-run-nl2sql-bq`), the main product used underneath (e.g., `cloud-run-*`), or a mix of both.
- **Sub-folders:** Each factory must contain exactly two stage folders: `0-prereqs` and `1-apps`.
- **0-prereqs Structure:** The `0-prereqs` folder structure is identical across all factories, with the exception of the templates inside `data/projects`, and occasionally `templates/terraform.auto.tfvars.tpl` or `outputs.tf` depending on the values passed to `1-apps`.
- **1-apps Structure:** The `1-apps` stage must always include an architecture diagram named `diagram.png`. This diagram must be linked in the `README.md` of `1-apps`.
- **Applications:** The `1-apps` stage may contain an `apps` subfolder for application code (e.g., Python) deployed on top of the infrastructure. Commands to deploy these apps must be returned to the user via Terraform outputs in `1-apps`.
- **Documentation:** The factory root folder, the `0-prereqs` stage, and the `1-apps` stage must all have a `README.md` file. These READMEs follow a standard logical structure consistent across the repository; review existing factories (e.g., `cloud-run-single`) to derive and replicate this structure.
- **Agent Instructions:** The factory root folder must include an `AGENTS.md` file documenting factory-specific architecture, key files, test commands, and implementation gotchas, and must be linked in the [Factory Index](#factory-index) above.

Each factory (folder) is split into two stages (which correspond to two Terraform modules and two sub-folders):

- **0-prereqs**: meant to be executed by infrastructure teams to prepare the project where the application team will deploy the resources and delegate permissions to the application team).
- **1-apps**: used by the application team to deploy the resources in the project created at the step before, with the identity created at the step before, that has been granted the roles needed at the step before.

### 0-prereqs

- It creates the project(s).
- It creates the service accounts used:
  - by the application team to run terraform in the next stage.
  - by the application itself, if needed (i.e., cloud run service account, cloud build service account).
- It creates the GCS buckets to store the Terraform state while applying the next stage.
- It enables APIs needed for the specific use case.
- It grants IAM roles to the service accounts created and to the service agents.

The stage contains one or more `.yaml` files within the `./data/projects` folder.
Each file contains the definition of a project to be created (and some other resources/roles that relate to it).

The stage asks users for a minimum set of values for some mandatory variables, declared in a `variables.tf` file.
For example, this includes (but is not limited to):

- The parent (either a folder or the organization id) under which the project(s) should be created.
- The region where regional resources will be deployed.

There are multiple ways users can prepare their projects:

- By running this stage, if users don't have their own project factory. The stage uses Fabric FAST application templates underneath and calls the [Cloud Foundation Fabric - Project Factory module](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory).
- If users run their own [FAST stage project factory](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast/stages/2-project-factory), they can do so by copying the yaml files from the `./data/projects` folder.
- If users have a custom project creation process, they can leverage the information contained within the `.yaml` files in the `./data/projects` folder.

If users run this stage, it automatically creates two files in the `1-apps` stage:

- A **providers.tf** file that tells the stage (Terraform module):
  - Which service account to impersonate to run Terraform.
  - Which GCS bucket to use to store the Terraform state and which service account to impersonate while writing the Terraform state file.
- A **terraform.auto.tfvars** file that provides the `1-apps` module some information to run (matching some of the variables declared in the `1-apps` module). For example, this includes (but is not limited to): the project id and number, the service accounts that applications (i.e. Cloud Run) should use, and more.

### 1-apps

The `1-apps` stage (Terraform module) has two goals:

- Deploy the platform resources via Terraform in the project(s) created at the previous stage.
- Deploy some sample AI applications on top of the infrastructure resources deployed. This is usually done via gcloud or curl commands.

The stage declares a set of variables in the file `variables.tf`.
If users create project(s) using the `0-prereqs` stage from genai-factory, some of these values are already present in a `terraform.auto.tfvars` file.
If users create project(s) outside genai-factory (instead of using `0-prereqs`), it's their responsibility to prepare the `providers.tf` and `terraform.auto.tfvars` files.
Values for other variables are specific to the stage itself and need to be added through a separate `terraform.tfvars` file (either created by the user or by automation tools running this stage).

Once users run `terraform apply`, the stage prints a set of output commands (usually `gcloud` or `curl`) to deploy sample AI applications on top of the deployed infrastructure. This repository focuses on AI infrastructure rather than AI application development. However, we provide examples so users can test the deployed infrastructure end-to-end. These examples also serve as comprehensive base templates that users can easily customize.
The commands to deploy the applications are independent of Terraform, as they are typically owned by an application team who deploys their stack separately, usually through their own CI/CD platform. These commands are meant to be run on the same machine used to deploy the platform during testing, or adapted for use in deployment tools for production environments.

## Development Workflow

All instructions to develop and run tests in this repository are contained in the [CONTRIBUTING.md](./CONTRIBUTING.md) file in the root of this repository. Here is a summary.

### Prerequisites

- **[Terraform](https://developer.hashicorp.com/terraform/install)** (or OpenTofu)
- **[Python](https://www.python.org/)** (3.13+)
- **[uv](https://docs.astral.sh/uv/getting-started/installation/)**
- **[gcloud](https://docs.cloud.google.com/sdk/docs/install-sdk)**
- **Dependencies:**
  You can install python dependencies to develop and run tests by using:
  ```bash
  uv sync --all-groups
  ```

### Formatting & Linting

Always format code and update documentation before committing.

Check format and linting by calling the pre-commit hook:

```shell
uv run pre-commit run --all-files
```

These are some common commands you can use to fix formatting and linting issues:

```shell
# Terraform formatting
terraform fmt \
  -recursive \
  .

# Python
uv run yapf . \
  --parallel \
  --recursive \
  --in-place \
  --exclude '*/.venv/*'

# Yaml
uv run yamlfix . \
  --exclude "**/templates/**" \
  --exclude "**/.terraform/**" \
  --exclude "**/.venv/**"

# Spelling
uv run codespell . \
  --write-changes
```

> **Note:** **Common gotcha — unsorted variables (`[SV]` error):** `check_documentation.py` requires variables in `variables.tf` to be in strict alphabetical order. When adding a new variable, insert it at the correct alphabetical position, not at the top of the file.

### Testing

Our testing philosophy is simple: test to ensure the code works and does not break due to dependency changes.

Tests are extensively explained in the [CONTRIBUTING.md](./CONTRIBUTING.md) file in this repository, in the paragraphs `Run tests`, `Tests structure`, `Generate the inventory for a factory module`.

In short:

- Tests live in the `tests` folder at the root of the repository.
- When a new factory is added, a corresponding test folder must be created. The folder name must match the factory name but use underscores instead of dashes (e.g., `cloud_run_single` for the `cloud-run-single` factory).
- Inside the factory test folder, create subfolders for each stage: `0_prereqs` and `1_apps` (note the underscore).
- Each stage folder needs a `tftest.yaml` defining the tests. The primary/default test should be named `simple`.
- Each test defined in `tftest.yaml` requires two corresponding files: a `terraform.tfvars` input file (e.g., `simple.tfvars`) and an expected inventory YAML output file (e.g., `simple.yaml`).
- They test that a terraform plan (inventory) is consistent and equal to the expected, given a terraform.tfvars in input.
- They are implemented using pytest and the tftest library.

These are common commands.

```shell
# Run all tests
pytest tests

# Run specific module factory
pytest tests/<factory_test_folder_name>

# Automatically generate an inventory file given a tfvars in input
uv run tools/plan_summary.py cloud-run-single/0-prereqs \
  tests/cloud_run_single/0_prereqs/simple.tfvars \
  > tests/cloud_run_single/0_prereqs/simple.yaml

# Format the generated inventory YAML so it passes yamllint
uv run yamlfix tests/cloud_run_single/0_prereqs/simple.yaml
```

> **Note:**
>
> - `tools/plan_summary.py` outputs unformatted YAML; always run `uv run yamlfix` on regenerated inventory files before running `pre-commit`.
> - If a local clone of `cloud-foundation-fabric` is available on disk, you can speed up `pytest` (or run offline) by rewriting the git URL via environment variables:
>   `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file:///path/to/cloud-foundation-fabric.insteadOf" GIT_CONFIG_VALUE_0="https://github.com/GoogleCloudPlatform/cloud-foundation-fabric.git" uv run pytest tests`

### Contributing

- **Branching:** Use `feat/<name-of-feature>` for features and `bug/<name-of-bug>` for bugs.
- **Commits:** Create atomic commits with clear messages.
- **Docs:** Do NOT manually edit the variables/outputs tables in READMEs; use `uv run tools/tfdoc.py`.

## Architecture & Conventions

- **Variables & Interfaces:**

  - Prefer object variables (e.g., `iam = { ... }`) over many individual scalar variables.
  - Design compact variable spaces by leveraging Terraform `optional()` function with defaults extensively.
  - Use maps instead of lists for multiple items to ensure stable keys in state and avoid `for_each` dynamic value issues.

- **Naming:** Never use random strings for resource naming. Always use a variable `name` across all modules/resources in the factory and an optional variable `prefix` for global resources.

- **File Structure:**

  - Use standard file division and naming: `main.tf`, `variables.tf`, `outputs.tf`.
  - When `main.tf` becomes too large, split it into multiple files using a descriptive filename. For example, `iam.tf`, `gcs.tf`, `mounts.tf`.

- **Style & Formatting:**

  - **Line Length:** Enforce a 79-character line length limit for legibility (relaxed for long resource attributes and descriptions).
  - **Ternary Operators & Functions:** Wrap complex ternary operators in parentheses and break lines to align `?` and `:`. Split function calls with many arguments across multiple lines.
  - **Locals Separation:** Use module-level locals for values referenced directly by resources/outputs. Use block-level "private" locals prefixed with an underscore (`_`) for intermediate transformations.
  - **Complex Transformations:** Move complex data transformations in `for` or `for_each` loops to `locals` to keep resource blocks clean.

- **Dependencies & Fabric Modules:**

  - We build factories using existing Cloud Foundation Fabric modules alongside plain Terraform resources.
  - The version of Fabric modules must be kept consistent across all modules used in all factories (usually pinned to the latest tag, e.g., `v45.1.0`).
  - An automated nightly GitHub workflow checks for new tags using `uv run tools/fetch_latest_tag.py`. If a new tag is found, it updates the references with `uv run tools/update_fabric_ref.py`, runs tests, and creates a PR if successful. These scripts can also be executed manually to update dependencies.

## Key Learnings & Best Practices

Cross-cutting learnings that apply across multiple factories are documented below. For factory-specific architecture, workarounds, and operational rules, consult the corresponding file in the [Factory Index](#factory-index).

### Private Networking & Regional/Multi-Regional APIs (`*.rep.googleapis.com`)

- **Private Google Access (`199.36.153.8/30`) Does Not Route `*.rep.googleapis.com`:**
  - The `private.googleapis.com` VIPs and wildcard DNS rules only route global `*.googleapis.com` traffic. Calls from private VPC workloads (Cloud Run with `PRIVATE_RANGES_ONLY` egress, Agent Engine with PSC-I, etc.) to regional or multi-regional endpoints (`<service>.<location>.rep.googleapis.com`) will fail with TLS certificate mismatch or connection timeouts unless a dedicated regional PSC endpoint (`google_network_connectivity_regional_endpoint`) and Cloud DNS response policy rule exist in the VPC.
- **Multi-Regional Vertex AI vs. Regional Infrastructure:**
  - Newer Gemini models (e.g., `gemini-4-argon`) are served on multi-regional Vertex AI endpoints (`eu` / `us`, i.e., `aiplatform.eu.rep.googleapis.com` and `aiplatform.us.rep.googleapis.com`), while infrastructure resources (Cloud Run, AlloyDB, Cloud SQL, Artifact Registry, Model Armor, Agent Engine) remain regional (`var.region`, e.g., `europe-west1`).
  - In `0-prereqs`, derive `multi_region = startswith(var.region, "europe") ? "eu" : "us"`, pass it to `1-apps` via `templates/terraform.auto.tfvars.tpl` (as `default_location` or `multi_region`), and provision a `google_network_connectivity_regional_endpoint` + Cloud DNS response policy rule for `aiplatform.${local.multi_region}.rep.googleapis.com`.
  - For strictly regional `.rep.googleapis.com` APIs (such as `modelarmor.${var.region}.rep.googleapis.com`), provision a separate regional PSC endpoint and DNS response policy rule in `0-prereqs/networking.tf`.
  - Whenever `google_network_connectivity_regional_endpoint` is used in `0-prereqs/networking.tf`, ensure `networkconnectivity.googleapis.com` is listed in `services` and `roles/networkconnectivity.regionalEndpointAdmin` is granted to the `service-01` RW service account in `0-prereqs/data/projects/host.yaml`.

### Models, GenAI SDK (`google-genai`), and ADK (`google-adk`)

- **Separating `REGION` and `GOOGLE_CLOUD_LOCATION`:**
  - `google-genai` (`genai.Client`) and `google-adk` automatically read `GOOGLE_CLOUD_LOCATION` from the environment. When an app interacts with both regional services (e.g., Model Armor in `europe-west1`) and multi-regional Vertex AI models (in `eu` or `us`), keep `REGION` (`europe-west1`) and `GOOGLE_CLOUD_LOCATION` (`eu` / `us`) as distinct environment variables.
- **Explicit Thinking Level (`THINKING_LEVEL`):**
  - Always expose `THINKING_LEVEL = os.environ.get("THINKING_LEVEL", "MEDIUM")` (or `LLM_THINKING_LEVEL` in RAG apps) in `src/config.py` and pass `thinking_config=types.ThinkingConfig(thinking_level=...)` inside `types.GenerateContentConfig(...)` so users can easily inspect and tune reasoning depth.
- **Embeddings (`gemini-embedding-001`):**
  - RAG factories default to `gemini-embedding-001` with `3072` dimensions.
  - `client.models.embed_content` enforces a limit of at most **250** inputs per request; always chunk document lists into batches (e.g., `<= 250`) during ingestion.

### End-to-End (E2E) Deployment & Application Gotchas

- **Stage 0 Delegation (`0-prereqs/data/projects/*.yaml`):**
  - Because `1-apps` runs Terraform and deployment commands by impersonating the Stage 0 `service-01` RW service account (`<prefix>-gf-...-01-rw@...`), any API or IAM permission required by `1-apps` resources or `gcloud` deployment commands must be declared in `0-prereqs/data/projects/service-01.yaml` (or `host.yaml` for Shared VPC host project resources).
- **`gcloud` Quota Project with Impersonation (`CLOUDSDK_BILLING_QUOTA_PROJECT`):**
  - When a local `gcloud` configuration has `billing/quota_project` set to a different project, `gcloud` commands using `--impersonate-service-account=iac-rw@<service-project>...` (such as `gcloud storage cp`) fail with `403 Permission 'serviceusage.services.use' denied`. Export `CLOUDSDK_BILLING_QUOTA_PROJECT=<service-project-id>` (or unset `billing/quota_project`) during E2E runs.
- **Cloud Run Direct VPC Egress IP Reservation on Teardown (`serverless-ipv4-cloudrun-*`):**
  - After destroying Cloud Run services or jobs in `1-apps` that use Direct VPC Egress on a Shared VPC subnet, Serverless retains the `/28` internal IP reservation (`serverless-ipv4-cloudrun-*`) for several minutes, blocking `0-prereqs` `terraform destroy` on Shared VPC detachment and subnet deletion (`resourceInUseByAnotherResource`). Deleting the service project first (or waiting for the reservation to release) unblocks `0-prereqs` teardown.
- **Cleaning Up Generated `1-apps/providers.tf` & `terraform.auto.tfvars` After E2E Tests:**
  - Leaving the `providers.tf` and `terraform.auto.tfvars` generated by `0-prereqs` inside `1-apps/` causes `pytest` and `tools/plan_summary.py` to fail (attempting to initialize the remote GCS backend); always remove them along with `.terraform*` and `terraform.tfstate*` after E2E teardown.
- **Python Lockfiles (`uv.lock`) in Container Builds:**
  - Sample app `Dockerfile`s run `uv sync --frozen`. Whenever `pyproject.toml` is modified in any sample application, run `uv lock` inside that application directory and commit the updated `uv.lock`; otherwise Cloud Build will fail during `gcloud builds submit` / `gcloud run deploy`.

## Preferred Workflow

- Always break down complex requests into small, iterative tasks.
- For each task, propose the necessary edits and explicitly wait for user confirmation or discussion before proceeding.
- Always use the `replace` tool to both perform and cleanly display the proposed text modifications. Do not silently overwrite files or use shell commands for text edits.
