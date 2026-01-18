# Expose an agent running on Agent Engine via Agent2Agent (A2A) Protocol

The application demonstrates the deployment of a simple agent running on Agent Engine and exposed via [Agent2Agent (A2A) Protocol](https://a2a-protocol.org/latest/).

## Access the Agent from Internet

```shell
# Access the agent card
export APP_ADDRESS=https://your-app-address

# Get Agent Card
curl -X GET ${APP_ADDRESS}/.well-known/agent-card.json \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)"
