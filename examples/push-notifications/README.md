# Push Notifications

Demonstrates asynchronous task processing with webhook-based push notification delivery for status and artifact updates.

## What it demonstrates

- Async background processing with `A2A::Store::Processor`
- Push notification config (inline via `SendMessage` and CRUD operations)
- Webhook delivery on state transitions and artifact creation
- Two-service setup: agent + webhook receiver
- Full push notification config CRUD: Create, Get, List, Delete

## Architecture

| Service | Port | Role |
|---|---|---|
| **agent** | 9292 | Processes jobs asynchronously, delivers webhook updates |
| **receiver** | 9293 | Minimal Rack app that logs incoming webhook payloads |

The agent always returns immediately with `SUBMITTED` state. Work runs in a background fiber, and each state transition triggers webhook delivery to registered push notification configs. The receiver logs all incoming webhooks to stdout.

## Running

```sh
cd examples/push-notifications
docker compose up --build
```

## Testing

Submit a job with an inline push notification config:

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Process this data"}]},
    "configuration":{"taskPushNotificationConfig":{
      "url":"http://receiver:9293/webhook",
      "token":"my-secret-token"
    }}
  }}'
```

Watch the receiver logs to see webhook deliveries as the task progresses through `WORKING` -> `COMPLETED`.

Poll for the final result:

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"GetTask","params":{"id":"TASK_ID_HERE"}}'
```

## Files

| File | Purpose |
|---|---|
| `agent/config.ru` | Agent -- async processing, push notification config CRUD, webhook delivery |
| `agent/falcon.rb` | Falcon config for agent (port 9292) |
| `receiver/config.ru` | Webhook receiver -- logs incoming POST payloads |
| `receiver/falcon.rb` | Falcon config for receiver (port 9293) |
| `Gemfile` | Shared dependencies |
| `Dockerfile.agent` | Container build for the agent service |
| `Dockerfile.receiver` | Container build for the receiver service |
| `docker-compose.yml` | Two-service compose config |
