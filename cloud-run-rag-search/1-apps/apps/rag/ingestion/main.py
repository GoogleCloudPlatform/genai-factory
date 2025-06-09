# Copyright 2025 Google LLC
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

import logging
import os
import pandas as pd
import sys
import time
from typing import List, Optional

from google.cloud import aiplatform
from google.cloud import storage
from google.cloud.aiplatform.matching_engine import MatchingEngineIndex
from vertexai.language_models import TextEmbeddingModel

from src import config


# --- Logging Setup ---
logging.basicConfig(level=logging.INFO,
                    format='%(name)s - %(levelname)s - %(message)s',
                    handlers=[logging.StreamHandler(sys.stdout)])
logger = logging.getLogger(__name__)

def download_csv_from_gcs(bucket_name: str, file_name: str) -> str:
    """Downloads a CSV file from GCS to a temporary local path."""
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    local_path = f"/tmp/{file_name}"
    blob.download_to_filename(local_path)
    print(f"Downloaded {file_name} from gs://{bucket_name} to {local_path}")
    return local_path

def generate_embeddings(
    model: TextEmbeddingModel, df: pd.DataFrame
) -> List[List[float]]:
    """Generates embeddings for the text content in a DataFrame."""
    all_embeddings = []
    df["content"] = df.apply(
        lambda row: f"Product Name: {row['name']}\nDescription: {row['description']}",
        axis=1,
    )

    print(f"Generating embeddings for {len(df)} documents...")
    # Process in batches
    for i in range(0, len(df), config.EMBEDDING_BATCH_SIZE):
        batch = df["content"][i : i + config.EMBEDDING_BATCH_SIZE].tolist()
        try:
            embeddings = model.get_embeddings(batch)
            all_embeddings.extend([e.values for e in embeddings])
            print(f"  - Generated embeddings for batch {i//config.EMBEDDING_BATCH_SIZE + 1}")
        except Exception as e:
            print(f"An error occurred during embedding generation: {e}")
            all_embeddings.extend([None] * len(batch))
        time.sleep(1) # Small delay to respect API rate limits

    return all_embeddings

def prepare_datapoints(df: pd.DataFrame) -> List[MatchingEngineIndex.Datapoint]:
    """Prepares the data in the format required for Vertex AI Search upsert."""
    datapoints = []
    print("Preparing datapoints for upsert...")
    for _, row in df.iterrows():
        if not row["embedding"]:
            print(f"Skipping datapoint with id {row['id']} due to missing embedding.")
            continue

        # Each datapoint needs an ID, the embedding vector, and metadata for filtering.
        datapoint = MatchingEngineIndex.Datapoint(
            datapoint_id=str(row["id"]),
            feature_vector=row["embedding"],
            # `restricts` are used for pre-filtering in searches.
            # `allow_list` is for string values (e.g., category == "Electronics")
            # `value_int` is for numeric values (e.g., stock_level > 100)
            restricts=[
                aiplatform.matching_engine.index_endpoint.Namespace(
                    "category", [str(row["category"])]
                ),
                aiplatform.matching_engine.index_endpoint.Namespace(
                    "brand", [str(row["brand"])]
                ),
            ],
            # `numeric_restricts` is for numeric filtering
            numeric_restricts=[
                aiplatform.matching_engine.index_endpoint.NumericNamespace(
                    "stock_level",
                    value_int=int(row["stock_level"]),
                )
            ]
        )
        datapoints.append(datapoint)
    return datapoints

def main():
    """Main function to run the data indexing job."""
    print("Starting Vertex AI Search update job...")
    aiplatform.init(project=config.PROJECT_ID, location=config.REGION)

    # 1. Download and Parse CSV
    local_csv_path = download_csv_from_gcs(config.GCS_BUCKET_NAME, config.GCS_CSV_FILENAME)
    df = pd.read_csv(local_csv_path)

    # 2. Generate Embeddings
    embedding_model = TextEmbeddingModel.from_pretrained(config.EMBEDDING_MODEL_NAME)
    df["embedding"] = generate_embeddings(embedding_model, df)

    # 3. Prepare Datapoints for Indexing
    datapoints_to_upsert = prepare_datapoints(df)

    if not datapoints_to_upsert:
        print("No valid datapoints to upsert. Exiting.")
        return

    # 4. Upsert to Vertex AI Search Index
    print(f"Connecting to Vertex AI Search Index: {config.INDEX_ID}")
    my_index = aiplatform.MatchingEngineIndex(index_name=config.INDEX_ID)

    print(f"Upserting {len(datapoints_to_upsert)} datapoints in batches of {config.UPSERT_BATCH_SIZE}...")
    for i in range(0, len(datapoints_to_upsert), config.UPSERT_BATCH_SIZE):
        batch_to_upsert = datapoints_to_upsert[i : i + config.UPSERT_BATCH_SIZE]
        try:
            my_index.upsert_datapoints(datapoints=batch_to_upsert)
            print(f"  - Successfully upserted batch {i//config.UPSERT_BATCH_SIZE + 1}")
        except Exception as e:
            print(f"An error occurred during upsert for batch {i//config.UPSERT_BATCH_SIZE + 1}: {e}")

    print("Job finished successfully!")

if __name__ == "__main__":
    main()
