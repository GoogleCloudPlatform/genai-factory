# Expose an agent running on Cloud Run via Agent2Agent (A2A) Protocol
The application demonstrates the deployment of a simple agent running on Cloud Run and exposed via [Agent2Agent (A2A) Protocol](https://a2a-protocol.org/latest/).

## Get Agent Card from public internet
In order to retrieve the Agent Card from the Internet, your domain should be valid. Alternatevely, you can also leverage an Internal Load Balancer and retrieve the Agent Card privately.

```shell
# This is your load balancer domain name
export APP_ADDRESS=https://your-app-address

# Get Agent Card
curl -X GET ${APP_ADDRESS}/.well-known/agent-card.json \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)"