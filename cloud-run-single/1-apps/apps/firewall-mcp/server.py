import os
import logging
from typing import List, Dict, Any, Optional
from fastmcp import FastMCP
from google.cloud import compute_v1
from google.api_core.exceptions import GoogleAPICallError

# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("firewall-mcp")

# Initialize FastMCP
mcp = FastMCP("GCP Firewall")

def _format_firewall(firewall: compute_v1.Firewall) -> Dict[str, Any]:
    """Format a Firewall rule into a dictionary."""
    return {
        "id": str(firewall.id),
        "name": firewall.name,
        "network": firewall.network,
        "priority": firewall.priority,
        "direction": firewall.direction,
        "source_ranges": list(firewall.source_ranges),
        "destination_ranges": list(firewall.destination_ranges),
        "source_tags": list(firewall.source_tags),
        "target_tags": list(firewall.target_tags),
        "source_service_accounts": list(firewall.source_service_accounts),
        "target_service_accounts": list(firewall.target_service_accounts),
        "allowed": [{"IPProtocol": allowed.I_p_protocol, "ports": list(allowed.ports)} for allowed in firewall.allowed],
        "denied": [{"IPProtocol": denied.I_p_protocol, "ports": list(denied.ports)} for denied in firewall.denied],
        "disabled": firewall.disabled,
        "description": firewall.description,
    }

@mcp.tool()
async def list_firewall_rules(project_id: str, filter: str = None) -> str:
    """List firewall rules for a project.
    
    Args:
        project_id: The Google Cloud Project ID.
        filter: Optional filter string (e.g., "name = 'my-rule'").
    """
    logger.info(f"Listing firewall rules for project: {project_id}, filter: {filter}")
    try:
        client = compute_v1.FirewallsClient()
        request = compute_v1.ListFirewallsRequest(project=project_id, filter=filter)
        page_result = client.list(request=request)
        
        rules = []
        for rule in page_result:
            rules.append(_format_firewall(rule))
            
        return str(rules)
    except Exception as e:
        logger.error(f"Error listing firewall rules: {e}")
        return f"Error: {str(e)}"

@mcp.tool()
async def list_networks(project_id: str) -> str:
    """List VPC networks in a project.
    
    Args:
        project_id: The Google Cloud Project ID.
    """
    logger.info(f"Listing networks for project: {project_id}")
    try:
        client = compute_v1.NetworksClient()
        request = compute_v1.ListNetworksRequest(project=project_id)
        page_result = client.list(request=request)
        
        networks = []
        for network in page_result:
            networks.append({
                "name": network.name,
                "self_link": network.self_link,
                "subnetworks": list(network.subnetworks) if network.subnetworks else []
            })
            
        return str(networks)
    except Exception as e:
        logger.error(f"Error listing networks: {e}")
        return f"Error: {str(e)}"

@mcp.tool()
async def create_firewall_rule(
    project_id: str, 
    name: str, 
    network: str = "global/networks/default",
    description: str = "",
    priority: int = 1000,
    direction: str = "INGRESS",
    source_ranges: List[str] = None,
    source_tags: List[str] = None,
    target_tags: List[str] = None,
    source_service_accounts: List[str] = None,
    target_service_accounts: List[str] = None,
    allow_tcp_ports: List[str] = None,
    deny_tcp_ports: List[str] = None
) -> str:
    """Create a new firewall rule.
    
    Args:
        project_id: Google Cloud Project ID.
        name: Name of the firewall rule.
        network: Network URL (e.g., "global/networks/default").
        description: Description of the rule.
        priority: Priority (0-65535). Lower is higher priority.
        direction: "INGRESS" or "EGRESS".
        source_ranges: List of source IP ranges (e.g., ["0.0.0.0/0"]).
        source_tags: List of source network tags.
        target_tags: List of target network tags.
        source_service_accounts: List of source service accounts.
        target_service_accounts: List of target service accounts.
        allow_tcp_ports: List of TCP ports to allow (e.g., ["80", "443"]).
        deny_tcp_ports: List of TCP ports to deny.
    """
    logger.info(f"Creating firewall rule {name} in {project_id}")
    try:
        client = compute_v1.FirewallsClient()
        firewall = compute_v1.Firewall()
        firewall.name = name
        firewall.network = network
        firewall.description = description
        firewall.priority = priority
        firewall.direction = direction
        
        if source_ranges:
            firewall.source_ranges = source_ranges
        if source_tags:
            firewall.source_tags = source_tags
        if target_tags:
            firewall.target_tags = target_tags
        if source_service_accounts:
            firewall.source_service_accounts = source_service_accounts
        if target_service_accounts:
            firewall.target_service_accounts = target_service_accounts
            
        if allow_tcp_ports:
            allow = compute_v1.Allowed()
            allow.I_p_protocol = "tcp"
            allow.ports = allow_tcp_ports
            firewall.allowed.append(allow)
            
        if deny_tcp_ports:
            deny = compute_v1.Denied()
            deny.I_p_protocol = "tcp"
            deny.ports = deny_tcp_ports
            firewall.denied.append(deny)

        op = client.insert(project=project_id, firewall_resource=firewall)
        op.result() # Wait for completion
        
        return f"Firewall rule {name} created successfully."
    except Exception as e:
        logger.error(f"Error creating firewall rule: {e}")
        return f"Error: {str(e)}"

@mcp.tool()
async def delete_firewall_rule(project_id: str, firewall_rule: str) -> str:
    """Delete a firewall rule.
    
    Args:
        project_id: Google Cloud Project ID.
        firewall_rule: Name of the firewall rule to delete.
    """
    logger.info(f"Deleting firewall rule {firewall_rule} in {project_id}")
    try:
        client = compute_v1.FirewallsClient()
        op = client.delete(project=project_id, firewall=firewall_rule)
        op.result()
        return f"Firewall rule {firewall_rule} deleted successfully."
    except Exception as e:
        logger.error(f"Error deleting firewall rule: {e}")
        return f"Error: {str(e)}"

@mcp.tool()
async def update_firewall_rule(
    project_id: str,
    firewall_rule: str,
    new_priority: int = None,
    new_source_ranges: List[str] = None,
    new_source_tags: List[str] = None,
    new_target_tags: List[str] = None,
    new_source_service_accounts: List[str] = None,
    new_target_service_accounts: List[str] = None
) -> str:
    """Update an existing firewall rule (patch).
    
    Args:
        project_id: Project ID.
        firewall_rule: Name of the rule to update.
        new_priority: New priority.
        new_source_ranges: New list of source ranges.
        new_source_tags: New list of source tags.
        new_target_tags: New list of target tags.
        new_source_service_accounts: New list of source service accounts.
        new_target_service_accounts: New list of target service accounts.
    """
    logger.info(f"Updating firewall rule {firewall_rule} in {project_id}")
    try:
        client = compute_v1.FirewallsClient()
        # Patch requires specifying the fields mask or sending a partial resource
        
        firewall = compute_v1.Firewall()
        firewall.name = firewall_rule 
        
        # We need to set fields we want to change
        if new_priority is not None:
            firewall.priority = new_priority
        if new_source_ranges is not None:
            firewall.source_ranges = new_source_ranges
        if new_source_tags is not None:
            firewall.source_tags = new_source_tags
        if new_target_tags is not None:
            firewall.target_tags = new_target_tags
        if new_source_service_accounts is not None:
            firewall.source_service_accounts = new_source_service_accounts
        if new_target_service_accounts is not None:
            firewall.target_service_accounts = new_target_service_accounts
            
        op = client.patch(project=project_id, firewall=firewall_rule, firewall_resource=firewall)
        op.result()
        return f"Firewall rule {firewall_rule} updated successfully."
    except Exception as e:
        logger.error(f"Error updating firewall rule: {e}")
        return f"Error: {str(e)}"

if __name__ == "__main__":
    import sys
    port = int(os.getenv("PORT", 8080))
    mcp.run(transport="http", host="0.0.0.0", port=port)
