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

# Code source and reworked from
# https://google.github.io/adk-docs/agents/llm-agents

import functools
from typing import Any

from google.cloud import bigquery

from src import config


@functools.lru_cache(maxsize=1)
def get_database_settings() -> dict[str, Any]:
    """Fetches schema and description from BigQuery and caches the result."""
    description, schema = get_bigquery_schema_and_samples()
    return {
        "data_project_id": config.BQ_DATA_PROJECT_ID,
        "dataset_id": config.BQ_DATASET_ID,
        "description": description,
        "schema": schema,
    }


def get_bigquery_schema_and_samples() -> tuple[str, dict[str, Any]]:
    """Retrieves schema and sample values for the BigQuery dataset tables."""
    client = bigquery.Client(project=config.BQ_COMPUTE_PROJECT_ID)
    dataset_ref = bigquery.DatasetReference(config.BQ_DATA_PROJECT_ID,
                                            config.BQ_DATASET_ID)
    description = client.get_dataset(dataset_ref).description or ""

    tables_context = {}
    for table in client.list_tables(dataset_ref):
        table_info = client.get_table(
            bigquery.TableReference(dataset_ref, table.table_id))
        table_schema = [(schema_field.name, schema_field.field_type)
                        for schema_field in table_info.schema]
        table_ref = dataset_ref.table(table.table_id)

        tables_context[str(table_ref)] = {
            "table_schema": table_schema,
        }

    return description, tables_context


def get_dataset_definitions_for_instructions(database_settings: dict) -> str:
    """Returns the dataset definitions instructions block"""

    schema_content = database_settings.get("schema", "")
    description_content = database_settings.get("description", "")

    dataset_definitions = f"""
<DATASETS>
<DESCRIPTION>
{description_content}
</DESCRIPTION>
<SCHEMA>
--------- The schema of the relevant database with a few sample rows. --------
{schema_content}
</SCHEMA>
</DATASETS>
"""

    if "cross_dataset_relations" in database_settings:
        dataset_definitions += f"""
<CROSS_DATASET_RELATIONS>
--------- The cross dataset relations between the configured datasets. ---------
{database_settings["cross_dataset_relations"]}
</CROSS_DATASET_RELATIONS>
"""

    return dataset_definitions
