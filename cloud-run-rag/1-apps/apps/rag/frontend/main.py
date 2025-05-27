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
from typing import Any, Dict
import sys

import pg8000
from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from google.cloud import modelarmor_v1
from google.cloud.sql.connector import Connector
from langchain_community.vectorstores.pgvector import PGVector
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import PromptTemplate
from langchain_core.runnables import (
    RunnableBranch,
    RunnableLambda,
    RunnableParallel,
    RunnablePassthrough,
)
from langchain_google_vertexai import VertexAI, VertexAIEmbeddings
from langserve import add_routes
import uvicorn


# Initialize logger
logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO) # Configure basic logging

# --- Configuration (Fetch from Environment Variables) ---
try:
    PROJECT_ID = os.environ["PROJECT_ID"]
    LOCATION = os.environ.get("MA_REGION", "europe-west1")
    MODEL_ARMOR_TEMPLATE_ID = os.environ.get("MA_TEMPLATE_ID", "")

    DB_INSTANCE_NAME = os.environ.get("DB_INSTANCE_NAME", "")
    DB_USER = os.environ.get("DB_USER", "")
    DB_PASS = os.environ.get("DB_PASS", "")
    DB_NAME = os.environ.get("DB_NAME", "")

    EMBEDDING_MODEL_NAME = os.environ.get("EMBEDDING_MODEL", "text-embedding-005")
    LLM_MODEL_NAME = os.environ.get("LLM_MODEL", "gemini-2.5-flash")

except KeyError as e:
    logging.error(f"Missing required environment variable: {e}")
    sys.exit(1)
except ValueError as e:
    logging.error(f"Error parsing numeric environment variable (e.g., DB_PORT, BATCH_SIZE_*, EMBEDDING_DIMENSIONS): {e}")
    sys.exit(1)

# --- FastAPI App Initialization ---
app = FastAPI()


@app.get("/")
async def redirect_root_to_playground():
    return RedirectResponse("/playground")

# (1) Initialize VectorStore
connector = Connector()

def getconn() -> pg8000.dbapi.Connection:
    conn: pg8000.dbapi.Connection = connector.connect(
        DB_INSTANCE_NAME,
        "pg8000",
        user=DB_USER,
        password=DB_PASS,
        db=DB_NAME,
    )
    return conn


vectorstore = PGVector(
    connection_string="postgresql+pg8000://",
    use_jsonb=True,
    engine_args=dict(
        creator=getconn,
    ),
    embedding_function=VertexAIEmbeddings(model_name=EMBEDDING_MODEL_NAME),
)

# (2) Build retriever
def concatenate_docs(docs):
  return "\n\n".join(doc.page_content for doc in docs)

notes_retriever = vectorstore.as_retriever() | concatenate_docs

# (3) Create prompt template
prompt_template = PromptTemplate.from_template(
    """You are a movie expert answering questions. 
Use the retrieved IMDB movies' titles, year and descriptions to answer questions
Give a concise answer, and if you are unsure of the answer, just say so.

Movie names: {notes}

Here is your question: {query}
Your answer: """
)

# (4) Initialize LLM
llm = VertexAI(
    model_name=LLM_MODEL_NAME,
    temperature=0.2,
    max_output_tokens=100,
    top_k=40,
    top_p=0.95,
)

# (5) Chain everything together
chain = (
    RunnableParallel({
        "notes": notes_retriever,
        "query": RunnablePassthrough()
    })
    | prompt_template
    | llm
    | StrOutputParser()
)

add_routes(app, chain)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))