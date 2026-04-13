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

All instructions to develop and run tests in this repository are contained in the [CONTRIBUTING.md](./CONTRIBUTING.md) file in the root of this repository.

### Prerequisites

*   **[Terraform](https://developer.hashicorp.com/terraform/install)** (or OpenTofu)
*   **[Python](https://www.python.org/)**
*   **[uv](https://docs.astral.sh/uv/getting-started/installation/)**
*   **[gcloud](https://docs.cloud.google.com/sdk/docs/install-sdk)**
*   **Dependencies:**
    You can install python dependencies to develop and run tests by using:
    ```bash
    uv sync --all-groups
    ```

### Common Tasks

#### 1. Formatting & Linting

Always format code and update documentation before committing.

```bash
# Format Terraform code (check then fix)
terraform fmt -check -recursive <factory-name>

# Check README consistency (variables table must match variables.tf)
python3 tools/check_documentation.py <factory-name>

# Regenerate README variables/outputs tables when check fails
# Note: tfdoc uses special HTML comments (<!-- BEGIN TFDOC -->) in READMEs. Do not manually edit these sections.
python3 tools/tfdoc.py --replace <factory-name>

# YAML linting
yamllint -c .yamllint --no-warnings <yaml-files>

# License/boilerplate check
python3 tools/check_boilerplate.py --scan-files <files>
```

**Common gotcha — unsorted variables (`[SV]` error):** `check_documentation.py` requires variables in `variables.tf` to be in strict alphabetical order. When adding a new variable, insert it at the correct alphabetical position, not at the top of the file.

#### 2. Testing

Our testing philosophy is simple: test to ensure the code works and does not break due to dependency changes. **Example-based testing via `README.md` is the preferred approach.** 

Tests are triggered from HCL Markdown fenced code blocks using a special `# tftest` directive at the end of the block.

```hcl
module "my-module" {
  source = "./modules/my-module"
  # ...
}
# tftest modules=1 resources=2 inventory=my-inventory.yaml
```

*   **Inventory files (`YAML`):** Used to assert specific values, resource counts, or outputs from the terraform plan against an expected dataset.
*   **Legacy Tests:** Python-based tests using `pytest` and `tftest` are supported but example-based tests should be used whenever possible.

```bash
# Run all tests
pytest tests

# Run specific module examples
pytest -k 'modules and <module-name>:' tests/examples

# Automatically generate an inventory file from a successful plan
pytest -s 'tests/examples/test_plan.py::test_example[terraform:modules/<module-name>:Heading Name:Index]'
```

**Note:** `TF_PLUGIN_CACHE_DIR` is recommended to speed up tests.

#### 3. Contributing

*   **Branching:** Use `username/feature-name`.
*   **Commits:** Atomic commits with clear messages.
*   **Docs:** Do not manually edit the variables/outputs tables in READMEs; use `tfdoc.py`.

## Adding Context Support to a Module

Several modules support symbolic variable interpolation via a `context` variable. This allows callers to pass symbolic references like `"$project_ids:myprj"` instead of raw values, which get resolved at plan time.

### Pattern

**1. Add a `context` variable** in `variables.tf` at its alphabetical position. Use keys relevant to the module — standard keys are `locations`, `networks`, `project_ids`, `subnets`; module-specific keys may be added (e.g., `kms_keys`, `artifact_registries`, `secrets`):

```hcl
variable "context" {
  description = "Context-specific interpolations."
  type = object({
    kms_keys    = optional(map(string), {})
    locations   = optional(map(string), {})
    networks    = optional(map(string), {})
    project_ids = optional(map(string), {})
  })
  default  = {}
  nullable = false
}
```

**2. Build `ctx` and `ctx_p` locals** in `main.tf`. If the module has IAM condition support, exclude `condition_vars` from the flattening (it is passed directly to `templatestring()`):

```hcl
locals {
  ctx = {
    for k, v in var.context : k => {
      for kk, vv in v : "${local.ctx_p}${k}:${kk}" => vv
    } # add: if k != "condition_vars"  — only when condition_vars is a key
  }
  ctx_p      = "$"
  project_id = lookup(local.ctx.project_ids, var.project_id, var.project_id)
  region     = lookup(local.ctx.locations, var.region, var.region)
}
```

**3. Apply lookups in resources.** Three patterns:

```hcl
# Simple field
project = local.project_id

# Nullable field (null must stay null, not looked up)
encryption_key_name = (
  var.encryption_key_name == null
  ? null
  : lookup(local.ctx.kms_keys, var.encryption_key_name, var.encryption_key_name)
)

# Deeply optional nested field
private_network = (
  try(var.network_config.psa_config.private_network, null) == null
  ? null
  : lookup(local.ctx.networks, var.network_config.psa_config.private_network,
      var.network_config.psa_config.private_network)
)

# Per-element list
nat_subnets = [for s in var.nat_subnets : lookup(local.ctx.subnets, s, s)]
```

**4. Long ternaries** are wrapped in parentheses with condition and branches on separate lines:

```hcl
ip_address = (
  var.address == null
  ? null
  : lookup(local.ctx.addresses, var.address, var.address)
)
```

### Tests

Add a `context` test alongside existing module tests:

- `tests/modules/<module_name>/tftest.yaml` — declare the module path and list `context:` under `tests:`
- `tests/modules/<module_name>/context.tfvars` — provide all required module variables using symbolic references; include a `context` block with maps that resolve them
- `tests/modules/<module_name>/context.yaml` — assert resolved (concrete) values in the plan output

### README example

Modify one existing README example (do not add a new one) to demonstrate context usage. The resolved values should match the existing inventory YAML so no inventory changes are needed.

## Architecture & Conventions

*   **Variables & Interfaces:** 
    *   Prefer object variables (e.g., `iam = { ... }`) over many individual scalar variables.
    *   Design compact variable spaces by leveraging Terraform's `optional()` function with defaults extensively.
    *   Use maps instead of lists for multiple items to ensure stable keys in state and avoid `for_each` dynamic value issues.
*   **Naming:** Never use random strings for resource naming. Rely on an optional `prefix` variable implemented consistently across modules.
*   **IAM:** Implemented within resources (authoritative `_binding` or additive `_member`) via standard interfaces.
*   **Outputs:** Explicitly depend on internal resources to ensure proper ordering (`depends_on`).
*   **File Structure:**
    *   Move away from `main.tf`, `variables.tf`, `outputs.tf`.
    *   Use descriptive filenames: `iam.tf`, `gcs.tf`, `mounts.tf`.
*   **Style & Formatting:**
    *   **Line Length:** Enforce a 79-character line length limit for legibility (relaxed for long resource attributes and descriptions).
    *   **Ternary Operators & Functions:** Wrap complex ternary operators in parentheses and break lines to align `?` and `:`. Split function calls with many arguments across multiple lines.
    *   **Locals Separation:** Use module-level locals for values referenced directly by resources/outputs. Use block-level "private" locals prefixed with an underscore (`_`) for intermediate transformations.
    *   **Complex Transformations:** Move complex data transformations in `for` or `for_each` loops to `locals` to keep resource blocks clean.

## Preferred Workflow

- Always break down complex requests into small, iterative tasks.
- For each task, propose the necessary edits and explicitly wait for user confirmation or discussion before proceeding.
- Always use the `replace` tool to both perform and cleanly display the proposed text modifications. Do not silently overwrite files or use shell commands for text edits.
