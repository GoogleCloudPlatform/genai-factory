# GenAI Factory

Genai-factory is a collection of **end-to-end blueprints to deploy generative AI infrastructures** in GCP, following security best-practices.

- Embraces IaC best practices. Infrastructure is implemented in [Terraform](https://developer.hashicorp.com/terraform), leveraging [Terraform resources](https://registry.terraform.io/providers/hashicorp/google/latest/docs) and [Cloud Foundations Fabric modules](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric).
- Follows the least-privilege principle: no default service accounts, primitive roles, minimal permissions.
- Compatible with [Cloud Foundation Fabric FAST](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast) [project-factory](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory) and application templates.

## Factories Structure

The repository is composed of multiple factories.
Each factory is a folder. The only folders that are not factories are `.github`, `tests`, `tools`.

Each factory (folder) splits in two stages (two Terraform modules / two sub-folders):

- **0-projects**: meant to be executed by infrastructure teams to prepare the project where the application team will deploy the resources and delegate permissions to the application team).
- **1-apps**: used by the application team to deploy the resources in the project created at the step before, with the identity created at the step before, that has been granted the roles needed at the step before.

### 0-projects

- It creates the project(s).
- It creates the service accounts used a) by the application team to run terraform in the next stage b) by the application itself, if needed (i.e. cloud run service account, cloud build service account).
- It created the GCS buckets to store the Terraform state while applying the next stage.
- It enables APIs needed for the specific use case.
- It grants IAM roles to the service accounts created and to the service agents.

The stage contains in the folder `./data/projects` one or more `.yaml` files.
Each file contains the definition of a project to be created (and some other resources/roles that related to it).

The stage asks users a minimum set of values for some mandatory variables, declared in a `variables.tf` file.
For example, this includes (but is not limited to) a) the parent (either a folder or the organization id) under which the project(s) should be created b) the region where to deploy the regional resources.

There are multiple ways users can prepare their projects:

- By running this stage, if users don't have their own project factory. The stage uses underneath Fabric FAST application templates and calls the [Cloud Foundation Fabric - Project Factory module](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/modules/project-factory).
- If users run their own [FAST stage project factory](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/master/fast/stages/2-project-factory), by copying the yaml files from the `./data/projects` folder.
- If users have their own custom way of creating projects, by leveraging information contained in the yaml files in the `./data/projects` folder.

If users run this stage, it also creates automatically two files in the `1-apps` stage:

- A **providers.tf** file that tells the stage (Terraform module) a) what service account to impersonate to run Terraform b) what GCS bucket to use to store the Terraform state and what service account to impersonate while writing the Terraform state file.
- A **terraform.auto.tfvars** file that provides the `1-apps` module some information to run (matching some of the variables declared in the `1-apps` module). For example, this includes (but is not limited to): the project id and number, the service accounts that applications (i.e. Cloud Run) should use, and more.

### 1-apps

The `1-apps` stage (Terraform module) has two goals:

- Deploy the platform resources via Terraform in the project(s) created at the previous stage.
- Deploy some sample AI applications on top of the infrastructure resources deployed. This is usually done via gcloud or curl commands.

The stage declares a set of variables in the file `variables.tf`.
If users create project(s) using the `0-projects` stage from genai-factory, some of these values are already present in a `terraform.auto.tfvars` file.
If users create project(s) outside genai-factory (instead of using `0-projects`), it's their responsibility to prepare the `providers.tf` and `terraform.auto.tfvars` files.
Values for other variables are specific to the stage itself and need to be added through a separate `terraform.tfvars` file (either created by the user or by automation tools running this stage).

Once users run `terraform apply`, the stage prints in output a set of commands (usually `gcloud` or `curl`) to deploy a set of AI applications on top of the infrastructure deployed. While this repository does not focus on AI application development, but rather on AI infrastructure development, we still show some examples, so that users a) can test end-to-end the infrastructure deployed b) they can leverage some basic but still enough comprehensive templates that they can easily customize.
The commands to deploy the applications have nothing to do with Terraform as they are usually owned by an application team, who deploys their application stack separately, usually in through their own CI/CD platform. These commands are meant to be run on the same machine of who deployed the platform in case of tests, or copied and pasted (and modified/extended) to any other tool, in case of production environments.

## Development Workflow

All instructions to develop and run tests in this repository are contained in the [CONTRIBUTING.md](./CONTRIBUTING.md) file in the root of this repository. Here is a summary.

### Prerequisites

- *[Terraform](https://developer.hashicorp.com/terraform/install)** (or OpenTofu)
- **[Python](https://www.python.org/)**
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

**Common gotcha — unsorted variables (`[SV]` error):** `check_documentation.py` requires variables in `variables.tf` to be in strict alphabetical order. When adding a new variable, insert it at the correct alphabetical position, not at the top of the file.

### Testing

Our testing philosophy is simple: test to ensure the code works and does not break due to dependency changes.

Tests are extensively explained in the [CONTRIBUTING.md](./CONTRIBUTING.md) file in this repository, in the paragraphs `Run tests`, `Tests structure`, `Generate the inventory for a factory module`.

In short:

- Tests live in the tests folder.
- They test that a terraform plan (inventory) is consistent and equal to the expected, given a terraform.tfvars in input.
- They are implemented using pytest and the tftest library.

These are common commands.

```shell
# Run all tests
pytest tests

# Run specific module factory
pytest tests/<factory_test_folder_name>

# Automatically generate an inventory file given a tfvars in input
uv run tools/plan_summary.py cloud-run-single/0-projects \
  tests/cloud_run_single/0_projects/simple.tfvars \
  > tests/cloud_run_single/0_projects/simple.yaml
```

### Contributing

- **Branching:** Use `feature-name`.
- **Commits:** Create atomic commits with clear messages.
- **Docs:** Do NOT manually edit the variables/outputs tables in READMEs; use `tfdoc.py`.

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

## Preferred Workflow

- Always break down complex requests into small, iterative tasks.
- For each task, propose the necessary edits and explicitly wait for user confirmation or discussion before proceeding.
- Always use the `replace` tool to both perform and cleanly display the proposed text modifications. Do not silently overwrite files or use shell commands for text edits.
