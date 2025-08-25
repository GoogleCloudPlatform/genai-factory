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
uv sync
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
# Generate tfdoc for cloud-run-single/0-projects
./tools/tfdoc.py cloud-run-single/0-projects
```

### Run tests

```shell
# Run all tests
uv run pytest tests

# Run tests for one cloud-run-single/0-projects
uv run pytest tests/cloud_run_single/0-projects
```

### Generate the inventory for a factory module

```shell
# Generate the inventory for cloud-run-single/0-projects
uv run tools/plan_summary.py cloud-run-single/0-projects \
  tests/cloud_run_single/0_projects/simple.tfvars
```

## Add a new factory

- Start copying an existing factory. [cloud-run-single](cloud-run-single/README.md) is a typical choice. Modify it as needed.
- Update the `uv pyproject.toml` to your needs.
  - Please check the [official documentation](https://docs.astral.sh/uv/getting-started/installation/#standalone-installer) on how to install `uv`. UV github actions are being used for the ci pipeline to run tests and tools.
  - Use the commands from the [section above](#manage-python-app-dependencies-with-uv)
  - You can learn how to use `uv` [here](https://docs.astral.sh/uv/#highlights).
  - Refer to [Dockerfiles](./cloud-run-single/1-apps/apps/chat/Dockerfile) from other applications in this repository to learn how to use `uv` with Docker.
- Create a corresponding test in the tests folder. 
  - Follow the example of other factories. For example, [this](tests/cloud_run_single/0_projects/tftest.yaml) is the test definition for 0-projects of the cloud-run-single factory.
  - Start creating an empty inventory with `values:` only. Then run the `tools/plan_summary.py` command (example [above](#generate-the-inventory-for-a-factory-module)) and update the inventory file with the output returned.
- Update the list of factories in the [main README.md](README.md).
