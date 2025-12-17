import asyncio
import argparse
import sys
import logging
import json
from typing import Optional, Dict, Any
from urllib.parse import urlparse

import subprocess
from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport
from fastmcp.client.auth import BearerAuth

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def get_id_token(url: str) -> Optional[str]:
    """
    Get a Google Cloud ID Token by invoking the gcloud CLI.
    This avoids direct dependencies on google-auth libraries.
    """
    try:
        result = subprocess.run(
            ["gcloud", "auth", "print-identity-token"],
            capture_output=True,
            text=True,
            check=True
        )
        token = result.stdout.strip()
        return token

    except subprocess.CalledProcessError as e:
        logger.error(f"Error fetching ID token via gcloud: {e.stderr}")
        return None
    except FileNotFoundError:
        logger.error("gcloud CLI not found. Please ensure Google Cloud SDK is installed and in your PATH.")
        return None

async def run_client(url: str, prompt: Optional[str] = None, tool_name: Optional[str] = None, tool_args: Optional[Dict[str, Any]] = None):
    """
    Connect to the MCP server via HTTP (Streamable) and interact using FastMCP Client.
    """
    
    logger.info(f"Connecting to {url}...")
    
    auth = None
    if url.startswith("http"):
        logger.info("Attempting to fetch ID token for authentication...")
        token = get_id_token(url)
        if token:
            auth = BearerAuth(token)
            logger.info("Successfully retrieved ID token.")
        else:
            logger.warning("Continuing without ID Token. If the server requires auth, this will fail.")

    try:
        transport = StreamableHttpTransport(url=url, auth=auth)
        async with Client(transport) as client:
            logger.info("Connected to MCP Server!")

            # List tools to verify connection
            logger.info("Listing available tools...")
            tools = await client.list_tools()
            for t in tools:
                print(f"- {t.name}: {t.description}")

            # Call tool if requested
            if tool_name:
                logger.info(f"Calling tool: {tool_name} with args {tool_args}")
                result = await client.call_tool(tool_name, arguments=tool_args or {})
                print("\n--- Result ---")
                if hasattr(result, "content"):
                     for content in result.content:
                        if hasattr(content, "text"):
                            print(content.text)
                        else:
                            print(content)
                else:
                    print(result)

    except Exception as e:
        logger.error(f"Connection failed: {e}")
        if hasattr(e, "response") and e.response:
             try:
                 print(f"\n[Debug] Response status: {e.response.status_code}")
                 print(f"[Debug] Response headers: {e.response.headers}")
                 print(f"[Debug] Response text: {e.response.text}")
             except Exception:
                 pass

        if "401" in str(e) or "403" in str(e):
             print("\n[!] Authentication failed. Try running: `gcloud auth print-identity-token` to verify you can get a token.")

def main():
    parser = argparse.ArgumentParser(description="Authenticated MCP Test Client (FastMCP HTTP)")
    parser.add_argument("url", help="URL of the MCP server (e.g., https://service.run.app/mcp)")
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    subparsers.add_parser("list", help="List available tools")
    
    call_parser = subparsers.add_parser("call", help="Call a specific tool")
    call_parser.add_argument("tool_name", help="Name of the tool to call")
    call_parser.add_argument("--args", help="JSON string of arguments", default="{}")
    call_parser.add_argument("--arg", action="append", help="Key=Value argument (can be used multiple times)")

    args = parser.parse_args()
    
    if not args.command:
        args.command = "list"

    tool_args = {}
    if args.command == "call":
        if args.args:
            try:
                tool_args = json.loads(args.args)
            except json.JSONDecodeError:
                logger.error("Invalid JSON in --args")
                sys.exit(1)
        
        if args.arg:
            for item in args.arg:
                if "=" in item:
                    k, v = item.split("=", 1)
                    tool_args[k] = v
    
    asyncio.run(run_client(
        args.url, 
        tool_name=args.tool_name if args.command == "call" else None,
        tool_args=tool_args
    ))

if __name__ == "__main__":
    main()
