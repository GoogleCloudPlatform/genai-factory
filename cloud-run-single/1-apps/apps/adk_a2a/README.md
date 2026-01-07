# Expose an agent running on Cloud Run via Agent2Agent (A2A) Protocol
The application demonstrates the deployment of a simple agent running on Cloud Run and exposed via [Agent2Agent (A2A) Protocol](https://a2a-protocol.org/latest/).

## Be sure your Cloud Run deployment accept requests from the internet
In order to accept requests from the Internet, your terraform.tfvars should include 

```shell
cloud_run_configs = {
  ingress = "INGRESS_TRAFFIC_ALL"
}

## Get Agent Card from public internet

```shell
# This is your load balancer domain name
export APP_ADDRESS=https://your-app-address

# Get Agent Card
curl -X GET ${APP_ADDRESS}/.well-known/agent-card.json \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)"