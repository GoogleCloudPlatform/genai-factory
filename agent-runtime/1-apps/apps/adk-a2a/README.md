# Agent Development Kit (ADK) sample application for Agent Runtime

The application demonstrates the deployment of [Agent Development Kit (ADK)](https://google.github.io/adk-docs) agents on Agent Runtime.

## Get the agent card

```shell
curl -X GET https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT_ID/.well-known/agent-card.json \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json"
```

Or via the A2A v1 card endpoint:

```shell
curl -X GET https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT_ID/a2a/v1/card \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json"
```

## Query the agent

```shell
TASK_ID=$(curl -X POST https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT_ID/a2a/v1/message:send \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{ "message": { "content": [{"text": "What is the exchange rate from US dollars to SEK on 2025-04-03?"}], "message_id": "remote-agent-message-id", "role": "1" } }' | jq -r '.task.id')
```

This will create a task that you can retrieve with another API call.

## Get task

```shell
curl -X GET https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT_ID/a2a/v1/tasks/$TASK_ID \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json"
```

## Caller identity and storage isolation

`AuthenticatedCallContextBuilder` ([`src/auth.py`](./src/auth.py)) verifies the incoming `Authorization: Bearer` (Google OIDC ID token or OAuth 2.0 access token) or IAP JWT header and binds the authenticated principal to `ServerCallContext`. Both `FirestoreSessionService` and `FirestoreTaskStore` scope document keys and verify stored ownership against that authenticated principal, ignoring client-supplied `message.metadata.user_id`.

## Documentation

More info on ADK can be found on the [official website](https://docs.cloud.google.com/agent-builder/agent-engine/develop/adk).
