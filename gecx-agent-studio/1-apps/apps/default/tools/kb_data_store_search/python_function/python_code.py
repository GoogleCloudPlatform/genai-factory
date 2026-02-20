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

from typing import Dict, Any


def kb_data_store_search(query: str) -> Dict[str, Any]:
    """Queries the brand's Knowledge Base and returns an answer for the given question. The result comes from a RAG system that will look for relevant snippets and generate the answer, if found.

    Args:
        query: The query to search for.

    Returns:
        The output of the datastore tool (answer and snippets)
    """
    request_body = {"query": query}

    # Add a brand filter if 'brand_code' is set
    if brand_code := context.state.get("ui__brand_code"):
        request_body["filter"] = f'brand_code: ANY("{brand_code}")'

    return tools.kb_data_store(request_body).json()
