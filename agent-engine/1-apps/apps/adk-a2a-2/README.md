# Agent Development Kit (ADK) sample application for Agent Engine

The application demonstrates the deployment of [Agent Development Kit (ADK)](https://google.github.io/adk-docs) agents on Agent Engine.

## Test the agent

You can test the agent using the following command.
A session will be automatically created for you.

```shell
curl -X POST https://$REGION-aiplatform.googleapis.com/v1/$AGENT_ID:streamQuery \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{ "input": { "message": "What is the exchange rate from US dollars to SEK on 2025-04-03?", "user_id": "user_123" } }'
```

## Documentation

More info on ADK can be found on the [official website](https://docs.cloud.google.com/agent-builder/agent-engine/develop/adk).
