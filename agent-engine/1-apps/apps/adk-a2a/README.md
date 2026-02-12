# Agent Development Kit (ADK) sample application for Agent Engine

The application demonstrates the deployment of [Agent Development Kit (ADK)](https://google.github.io/adk-docs) agents on Agent Engine.

## Get the agent card

```shell
curl -X GET https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT_ID/a2a/v1/card \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json"
```

## Documentation

More info on ADK can be found on the [official website](https://docs.cloud.google.com/agent-builder/agent-engine/develop/adk).
