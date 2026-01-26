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

from kfp import dsl
from kfp import compiler

@dsl.component(base_image="us-docker.pkg.dev/vertex-ai/training/scikit-learn-cpu.0-23:latest", packages_to_install=["kfp==2.7.0"])
def hello_world_component() -> str:
    import logging
    import sys
    import os
    
    logging.basicConfig(stream=sys.stdout, level=logging.INFO)
    logger = logging.getLogger("hello_world")

    logger.info("HELLO WORLD - Basic connectivity test")
    logger.info(f"Environment: {os.environ}")
    
    return "Hello World Success"

@dsl.pipeline(
    name="hello-world-pipeline",
    description="A simple Hello World pipeline for connectivity testing."
)
def private_data_pipeline():
    hello_task = hello_world_component()

if __name__ == "__main__":
    compiler.Compiler().compile(
        pipeline_func=private_data_pipeline,
        package_path="pipeline.yaml"
    )
    print("Pipeline compiled successfully to pipeline.yaml")
