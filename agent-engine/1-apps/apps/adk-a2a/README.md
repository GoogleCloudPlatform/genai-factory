# Agent Development Kit (ADK) sample application for Agent Engine

The application demonstrates the deployment of [Agent Development Kit (ADK)](https://google.github.io/adk-docs) agents on Agent Engine.

## Get the agent card

```shell
curl -X GET https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT_ID/a2a/v1/card \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json"
```


## Query the agent

```shell
curl -X POST https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT_ID/a2a/v1/message:send \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{ "message": { "content": [{"text": "What is the exchange rate from US dollars to SEK on 2025-04-03?"}], "message_id": "remote-agent-message-id", "role": "1" } }'
```

This will create a task that you can retrieve with another API call.

## Get task

```shell
curl -X GET https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT_ID/a2a/v1/tasks/YOUR_TASK_ID \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json"
```

## Documentation

More info on ADK can be found on the [official website](https://docs.cloud.google.com/agent-builder/agent-engine/develop/adk).
