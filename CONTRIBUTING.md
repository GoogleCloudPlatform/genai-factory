# Contributing

Thank you for considering contributing to this project!

We welcome contributions of all kinds. To get started:

1. **Sign [Google CLA](https://cla.developers.google.com/about/google-individual)**
2. **Fork the repository** on GitHub.
3. **Make your changes** in a new branch.
4. **Submit a pull request** with a clear description of your changes.

We will review your pull request and provide feedback as soon as possible.

Thank you for your contributions!

## Diagrams

We draw factory diagrams leveraging Google Slides.
You can find the diagrams file [here](https://docs.google.com/presentation/d/1I7-OQ60DD__MtfdUtw_bPkiRADN7NEmVKCl1OxfzTNA). The deck is private and you will need to request access.
When drawing new diagrams you can leverage the [official Google Cloud Icons deck](https://docs.google.com/presentation/d/1fD1AwQo4E9Un6012zyPEb7NvUAGlzF6L-vo5DbUe4NQ).

## Prerequisites:

- *[python](https://www.python.org/downloads/)* - Needed by gcloud and the programming language we use to develop the sample apps.
- *[terraform](https://developer.hashicorp.com/terraform/install)* - Infrastructure as Code tool
- *[gcloud](https://cloud.google.com/sdk/docs/install)* - Command line utility to authenticate and interact with Google Cloud

## Useful Commands

These are some useful commands that you may need during different phases of the development.

### Setup the development environment

```shell
uv sync --all-groups
```

### Manage Python app dependencies with uv

```shell
# Initialize the environment
uv init

# Add dependencies
uv add <dependency>
...
```

### Generate tfdoc

```shell
# Generate tfdoc for cloud-run-single/0-prereqs
./tools/tfdoc.py cloud-run-single/0-prereqs
```

### Run linting

We created a pre-commit hook that quickly executes all checks automatically before every commit.
You can install it by using:

```shell
uv run pre-commit install
```

You can also trigger all the checks manually, running:

```shell
uv run pre-commit run --all-files
```

The checks control both format and linting for Terraform, Python and Yaml.
They also check for the presence of copyright headers at the top of each file, misspelled words, missing empty lines at the end of files, broken links, and more.

For a full list of tests, look at the [.pre-commit-config.yaml config file](.pre-commit-config.yaml) or at the [Github linting.yml workflow file](./.github/workflows/linting.yml).

These are some commands people often use to fix linting errors:

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

### Run tests

We run Terraform tests by leveraging pytest and the [tftest framework](https://pypi.org/project/tftest/).

These Terraform tests verify for each stage in each factory that, given a set of `terraform.tfvars` in input, we get a plan with the expected outputs (meaning, expected number of modules and resources to be created, expected arguments and variables, expected outputs). We call these expected output files inventories.

Run tests by using these commands:

```shell
# Run all tests
uv run pytest tests

# Run tests for one factory stage. For example, cloud-run-single/0-prereqs
uv run pytest tests/cloud_run_single/0-prereqs
```

### Tests structure

Tests are defined in the `tests` folder, in the root of this repository.

Each factory has a dedicated test folder under `test` that needs to be named as the factory.
If the factory name includes dashes (`-`), these need to be substituted with underscores (`_`).
For example, the `agent-engine` factory has a corresponding `agent_engine` test folder.

Each factory test folder includes a subfolder for each stage: `0_prereqs` and `1_apps`.
Inside these folders there must be always a `tftest.yaml` file that declares the tests. For example:

```yaml
module: agent-engine/1-apps
tests:
  simple:
  a2a:
```

Each test needs two files, called as the test:

- A terraform.tfvars file
- An inventory yaml file

### Generate the inventory for a factory module

To generate the inventory (expected output) file for a test, given an input tfvars file, run:

```shell
# Generate the inventory for cloud-run-single/0-prereqs
uv run tools/plan_summary.py cloud-run-single/0-prereqs \
  tests/cloud_run_single/0_prereqs/simple.tfvars \
  > tests/cloud_run_single/0_prereqs/simple.yaml
```

After you generated the inventory file, remember to:

- Add the copyright at the top of the file. You can copy it from any other yaml file in this repository.
- Remove the following line, if you are generating the inventory for a `0_prereqs` stage: `.values.google_service_account_iam_member.me_sa_token_creator[0].member`:

## Add new factories

To add a new factory, follow these steps:

- Start by copying an existing factory. [cloud-run-single](cloud-run-single/README.md) is a typical choice. Modify it as needed.
- Update the uv `pyproject.toml` to your needs.
  - Please check the [official documentation](https://docs.astral.sh/uv/getting-started/installation/#standalone-installer) on how to install `uv`.
  - Use the commands from the [section above](#manage-python-app-dependencies-with-uv)
  - You can learn how to use `uv` [here](https://docs.astral.sh/uv/#highlights).
  - Refer to [Dockerfiles](./cloud-run-single/1-apps/apps/chat/Dockerfile) from other applications in this repository to learn how to use `uv` with Docker.
- Create corresponding tests in the `tests` folder.
  - Follow the example of other factories. For example, [this](tests/cloud_run_single/0_prereqs/tftest.yaml) is the test definition for 0-prereqs of the `cloud-run-single` factory. Refer to the test section for more details.
- Update the list of factories in the [main README.md](README.md).
