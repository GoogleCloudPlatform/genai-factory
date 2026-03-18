# Sample MCP Server for Cloud Run

The application shows how to implement a sample [Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) server on Cloud Run to communicate with GCP APIs by using users' credentials (access token from the request header). In this example, the MCP server controls GCP firewall rules.

## Roles needed

Make sure you assign to the caller the `compute.securityAdmin` role or any equivalent set of permission to allow the control of firewall rules.

## Use the application

You can test this MCP server by using the client script included in this folder:

```shell
# List available tools
uv run client.py https://YOUR_DOMAIN/mcp list

# Call a tool
uv run client.py https://YOUR_DOMAIN/mcp call list_firewall_rules --arg project_id=YOUR_PROJECT_ID
```
