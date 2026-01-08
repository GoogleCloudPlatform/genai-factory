# Firewall MCP Server for Cloud Run

A Model Context Protocol (MCP) server for managing Google Cloud Firewall rules, built with FastMCP.

## Use the application

You can test the server using the included client script:

```shell
# List available tools
uv run client.py https://YOUR_DOMAIN/mcp list

# Call a tool
uv run client.py https://YOUR_DOMAIN/mcp call list_firewall_rules --arg project_id=YOUR_PROJECT_ID
```