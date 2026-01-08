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

@dsl.component
def hello_world_component(name: str) -> str:
    greeting = f"Hello, {name}!"
    print(greeting)
    return greeting

@dsl.pipeline(
    name="hello-world-pipeline",
    description="A simple Hello World Vertex AI pipeline."
)
def hello_world_pipeline(name: str = "World"):
    hello_task = hello_world_component(name=name)

if __name__ == "__main__":
    compiler.Compiler().compile(
        pipeline_func=hello_world_pipeline,
        package_path="pipeline.yaml"
    )
    print("Pipeline compiled successfully to pipeline.yaml")
