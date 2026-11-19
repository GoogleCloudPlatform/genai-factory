# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Regression tests ensuring service-account impersonation roles stay SA-scoped."""

from pathlib import Path
from typing import Any

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]

DISALLOWED_PROJECT_SCOPED_SA_ROLES = frozenset({
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.serviceAccountTokenCreator",
    "roles/iam.serviceAccountUser",
    "roles/iam.workloadIdentityUser",
})


def _project_yaml_files() -> list[Path]:
  files = sorted(REPO_ROOT.glob("*/0-prereqs/data/projects/*.yaml"))
  assert files, "Expected at least one 0-prereqs project YAML file."
  return files


def _prereqs_inventory_files() -> list[Path]:
  files = [
      p for p in sorted(REPO_ROOT.glob("tests/*/0_prereqs/*.yaml"))
      if p.name != "tftest.yaml"
  ]
  assert files, "Expected at least one 0_prereqs plan inventory YAML file."
  return files


@pytest.mark.parametrize(
    "yaml_path",
    _project_yaml_files(),
    ids=lambda p: str(p.relative_to(REPO_ROOT)),
)
def test_no_project_scoped_sa_impersonation_roles_in_project_yamls(
    yaml_path: Path,) -> None:
  data: dict[str, Any] = yaml.safe_load(yaml_path.read_text()) or {}

  for role in (data.get("iam") or {}):
    assert role not in DISALLOWED_PROJECT_SCOPED_SA_ROLES, (
        f"{yaml_path}: {role} must be scoped to specific service accounts via "
        "iam_sa_roles, not granted project-wide under 'iam'.")

  for principal, roles in (data.get("iam_by_principals") or {}).items():
    for role in (roles or []):
      assert role not in DISALLOWED_PROJECT_SCOPED_SA_ROLES, (
          f"{yaml_path}: {principal} granted {role} project-wide under "
          "'iam_by_principals'; scope via service_accounts.<sa>.iam_sa_roles.")

  for key, binding in (data.get("iam_bindings") or {}).items():
    role = (binding or {}).get("role")
    assert role not in DISALLOWED_PROJECT_SCOPED_SA_ROLES, (
        f"{yaml_path}: iam_bindings[{key!r}] grants {role} project-wide.")

  for key, binding in (data.get("iam_bindings_additive") or {}).items():
    role = (binding or {}).get("role")
    assert role not in DISALLOWED_PROJECT_SCOPED_SA_ROLES, (
        f"{yaml_path}: iam_bindings_additive[{key!r}] grants {role} "
        "project-wide.")


@pytest.mark.parametrize(
    "inventory_path",
    _prereqs_inventory_files(),
    ids=lambda p: str(p.relative_to(REPO_ROOT)),
)
def test_no_project_scoped_sa_impersonation_in_prereqs_inventories(
    inventory_path: Path,) -> None:
  inventory: dict[str, Any] = yaml.safe_load(inventory_path.read_text()) or {}
  values: dict[str, Any] = inventory.get("values") or {}

  for addr, attrs in values.items():
    if ".google_project_iam_" not in addr and not addr.startswith(
        "google_project_iam_"):
      continue
    role = (attrs or {}).get("role")
    assert role not in DISALLOWED_PROJECT_SCOPED_SA_ROLES, (
        f"{inventory_path}: resource {addr} grants {role} at project scope.")


@pytest.mark.parametrize(
    ("factory_dir", "test_dir", "project_suffix"),
    [
        ("cloud-run-single", "cloud_run_single", "gf-srun-0"),
        ("serve-private-models", "serve_private_models", "gf-mg-0"),
    ],
)
def test_crun_build_sa_user_scoped_only_to_crun_runtime_sa(
    factory_dir: str,
    test_dir: str,
    project_suffix: str,
) -> None:
  svc_yaml = (REPO_ROOT / factory_dir /
              "0-prereqs/data/projects/service-01.yaml")
  data = yaml.safe_load(svc_yaml.read_text())

  build_sa_cfg = data["service_accounts"]["crun-build-0"]
  assert build_sa_cfg.get("iam_sa_roles") == {
      "$service_account_ids:service-01/crun-0": [
          "roles/iam.serviceAccountUser"
      ]
  }

  for inv_name in ("simple.yaml", "no_host_prj.yaml"):
    inv_path = REPO_ROOT / "tests" / test_dir / "0_prereqs" / inv_name
    values = yaml.safe_load(inv_path.read_text())["values"]

    build_member = (f"serviceAccount:crun-build-0@your-prefix-{project_suffix}"
                    ".iam.gserviceaccount.com")
    crun_sa_id = (
        f"projects/your-prefix-{project_suffix}/serviceAccounts/"
        f"crun-0@your-prefix-{project_suffix}.iam.gserviceaccount.com")
    iac_sa_id = (f"projects/your-prefix-{project_suffix}/serviceAccounts/"
                 f"iac-rw@your-prefix-{project_suffix}.iam.gserviceaccount.com")

    build_sa_grants = [
        attrs for addr, attrs in values.items()
        if 'module.service-accounts-iam["service-01/crun-build-0"]' in addr or
        ("google_service_account_iam_" in addr and
         (attrs.get("member") == build_member or build_member in
          (attrs.get("members") or [])))
    ]
    assert len(build_sa_grants) == 1
    assert build_sa_grants[0]["role"] == "roles/iam.serviceAccountUser"
    assert build_sa_grants[0]["service_account_id"] == crun_sa_id
    assert build_sa_grants[0]["service_account_id"] != iac_sa_id
