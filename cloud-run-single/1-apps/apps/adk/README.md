# Agent Development Kit (ADK) sample application for Cloud Run

The application demonstrates the deployment of [Agent Development Kit (ADK)](https://google.github.io/adk-docs) agents on Cloud Run.

## Use the application

```shell
# This is your load balancer domain name
export APP_ADDRESS=https://your-app-address

# List agents
curl -X GET ${APP_ADDRESS}/list-apps \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)"

# Create or update a user session for capital_agent
curl -X POST ${APP_ADDRESS}/apps/capital_agent/users/user_123/sessions/session_abc \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{"state": {"preferred_language": "English", "visit_count": 5}}'

# Query capital_agent
curl -X POST ${APP_ADDRESS}/run_sse \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{
    "app_name": "capital_agent",
    "user_id": "user_123",
    "session_id": "session_abc",
    "new_message": {
        "role": "user",
        "parts": [{
        "text": "What is the capital of Canada?"
        }]
    },
    "streaming": false
    }'
```

## UI Access

You can optionally enable the UI by setting the `SERVE_WEB_INTERFACE` [environment variable](./src/config.py) to `True`. Once it's done, simply point your browser to your application URL.

## Environment variables

Refer to [./src/config.py](./src/config.py) for the list of environment variables and defaults.

## Documentation

More info on ADK can be found on the [official website](https://google.github.io/adk-docs).
