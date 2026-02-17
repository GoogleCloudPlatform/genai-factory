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
