import logging
import os
from urllib.parse import urlparse

import uvicorn
from google.adk.a2a.utils.agent_to_a2a import to_a2a
from .agent.a2a_agent import root_agent

logging.basicConfig(level=logging.INFO)

INTERNAL_PORT = int(os.environ.get("PORT", 8003))
INTERNAL_HOST = "0.0.0.0"

A2A_URL = os.environ.get("A2A_URL", "localhost")
A2A_PORT = 443
A2A_PROTOCOL = "https"
parsed_url = urlparse(A2A_URL)
A2A_HOST = parsed_url.netloc or A2A_URL

logging.info(f"A2A_URL: {A2A_URL}")
logging.info(f"A2A_PROTOCOL: {A2A_PROTOCOL}")
logging.info(f"A2A_PORT: {A2A_PORT}")
logging.info(f"INTERNAL_PORT: {INTERNAL_PORT}")
logging.info(f"INTERNAL_HOST: {INTERNAL_HOST}")

a2a_app = to_a2a(agent=root_agent, protocol=A2A_PROTOCOL, host=A2A_HOST, port=A2A_PORT)

if __name__ == "__main__":
    uvicorn.run(a2a_app, host=INTERNAL_HOST, port=INTERNAL_PORT)