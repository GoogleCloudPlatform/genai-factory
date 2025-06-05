# Contributing

Thank you for considering contributing to this project!

We welcome contributions of all kinds. To get started:

1. **Sign [Google CLA](https://cla.developers.google.com/about/google-individual)**
2. **Fork the repository** on GitHub.
3. **Make your changes** in a new branch.
4. **Submit a pull request** with a clear description of your changes.

We will review your pull request and provide feedback as soon as possible.

Thank you for your contributions!

## Useful Commands

Setup dev environment

```shell
python3 -m venv ~/.venv-genai-factory
source ~/.venv-genai-factory/bin/activate

pip install -r tests/requirements.txt
pip install -r tools/requirements.txt
```

Generate tfdoc (example for `cloud-run-single`)

```shell
./tools/tfdoc.py modules/cloud-run-single
```

Run tests

```shell
# Run all tests
pytest tests

# Run a test for one module only
pytest tests/cloud_run_single/0-projects
```

Generate inventory for a factory module (example with cloud-run-rag/0-projects)

```shell
python tools/plan_summary.py cloud-run-rag/0-projects \
  tests/cloud_run_rag/0_projects/simple.tfvars
```

## Add a new factory

- Start copying an existing factory. [cloud-run-single](cloud-run-single/README.md) is a typical choice. Modify it as needed.
- Create a corresponding test in the tests folder. 
  - Follow the example of other factories. For example, [this](tests/cloud_run_single/0_projects/tftest.yaml) is the test definition for 0-projects of the cloud-run-single factory.
  - Start creating an empty inventory with `values:` only. Then run the `tools/plan_summary.py` command (example above) and update the inventory file with the output returned.
- Update the list of factories in the [main README.md](README.md).
