# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Pytest plugin to discover tests specified in YAML files.

This plugin uses the pytest_collect_file hook to collect all files
matching tftest*.yaml and runs plan_validate for each test found.

"""

import fnmatch
import json
import re
from pathlib import Path

import jsonschema
import pytest
import yaml

from .utils import get_tftest_directive
from .fixtures import plan_summary, plan_validator

_REPO_ROOT = Path(__file__).parents[1]


class TestFile(pytest.File):

  def collect(self):
    """Read yaml test spec and yield test items for each test definition.

    The test spec should contain a `module` key with the path of the
    terraform module to test, relative to the root of the repository

    Tests are defined within the top-level `tests` key, and should
    have the following structure:

    test-name:
      extra_files:
        - bar.tf
        - foo.tf
      tfvars:
        - tfvars1.tfvars
        - tfvars2.tfvars
      inventory:
        - inventory1.yaml
        - inventory2.yaml

    All paths specifications are relative to the location of the test
    spec. The inventory key is optional, if omitted, the inventory
    will be taken from the file test-name.yaml

    """

    try:
      raw = yaml.safe_load(self.path.open())
      module = raw.pop('module')
    except (IOError, OSError, yaml.YAMLError) as e:
      raise Exception(f'cannot read test spec {self.path}: {e}')
    except KeyError as e:
      raise Exception(f'`module` key not found in {self.path}: {e}')
    common = raw.pop('common_tfvars', [])
    for test_name, spec in raw.get('tests', {}).items():
      spec = {} if spec is None else spec
      extra_dirs = spec.get('extra_dirs')
      extra_files = spec.get('extra_files')
      inventories = spec.get('inventory', [f'{test_name}.yaml'])
      tf_var_files = common + [f'{test_name}.tfvars'] + spec.get('tfvars', [])
      for i in inventories:
        name = test_name
        if isinstance(inventories, list) and len(inventories) > 1:
          name = f'{test_name}[{i}]'
        yield TestItem.from_parent(self, name=name, module=module,
                                         inventory=[i],
                                         tf_var_files=tf_var_files,
                                         extra_files=extra_files,
                                         extra_dirs=extra_dirs)


class TestItem(pytest.Item):

  def __init__(self, name, parent, module, inventory, tf_var_files,
               extra_files=None, extra_dirs=None):
    super().__init__(name, parent)
    self.module = module
    self.inventory = inventory
    self.tf_var_files = tf_var_files
    self.extra_dirs = extra_dirs
    self.extra_files = extra_files

  def runtest(self):
    try:
      summary = plan_validator(self.module, self.inventory,
                               self.parent.path.parent, self.tf_var_files,
                               self.extra_files, self.extra_dirs)
    except AssertionError:

      def full_paths(x):
        return [str(self.parent.path.parent / x) for x in x]

      print(f'Error in inventory file: {" ".join(full_paths(self.inventory))}')
      print(
          f'To regenerate inventory run: python tools/plan_summary.py {self.module} {" ".join(full_paths(self.tf_var_files))}'
      )
      raise

  def reportinfo(self):
    return self.path, None, self.name


def pytest_collect_file(parent, file_path):
  'Collect tftest*.yaml files and run plan_validator from them.'
  if file_path.suffix == '.yaml' and file_path.name.startswith('tftest'):
    return TestFile.from_parent(parent, path=file_path)
