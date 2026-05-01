# Push Notifications

Demonstrates asynchronous task processing with webhook-based push notification delivery for status and artifact updates.

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/push-notifications)

## What you'll learn

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

## Step 1: Start both services

```sh
git clone https://github.com/general-intelligence-systems/a2a.git
cd a2a/examples/push-notifications
docker compose up -d --build
```

Expected output:

```
[+] Building 15.2s (18/18) FINISHED
[+] Running 2/2
 ✔ Container push-notifications-receiver-1  Started
 ✔ Container push-notifications-agent-1     Started
```

## Step 2: Check the logs

```sh
docker compose logs
```

Expected output:

```
receiver-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
receiver-1  |                | Webhook Receiver starting on :9293...
receiver-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
receiver-1  |                | POST webhooks to http://receiver:9293/webhook
agent-1     |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1     |                | Webhook Worker starting...
agent-1     |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1     |                | Push notifications example: async processing + webhook delivery
```

Both services should be running. The receiver is waiting for webhook POSTs on port 9293.

## Step 3: Submit a job with an inline push notification config

```sh
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Process this data"}]},
    "configuration":{"taskPushNotificationConfig":{
      "url":"http://receiver:9293/webhook",
      "token":"my-secret-token"
    }}
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "task": {
      "id": "be85b851-1234-5678-9abc-def012345678",
      "contextId": "a1b2c3d4-5678-9abc-def0-123456789abc",
      "status": {
        "state": "TASK_STATE_SUBMITTED",
        "timestamp": "2025-05-01T12:00:01.234Z"
      }
    }
  }
}
```

The response returns immediately with `TASK_STATE_SUBMITTED`. The work is now running in a background fiber. **Copy the `task.id` value** for later steps.

## Step 4: Watch the receiver logs for webhook deliveries

Wait 2-3 seconds for the background work to complete, then check the receiver logs:

```sh
docker compose logs receiver
```

Expected output:

```
receiver-1  |   1.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:02 +0000]
receiver-1  |                | Webhook received!
receiver-1  |   1.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:02 +0000]
receiver-1  |                |   Token: my-secret-token
receiver-1  |   1.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:02 +0000]
receiver-1  |                |   Payload: {
receiver-1  |                |     "taskId": "be85b851-...",
receiver-1  |                |     "status": {
receiver-1  |                |       "state": "TASK_STATE_WORKING",
receiver-1  |                |       "timestamp": "2025-05-01T12:00:02.000Z",
receiver-1  |                |       "message": {
receiver-1  |                |         "messageId": "...",
receiver-1  |                |         "role": "ROLE_AGENT",
receiver-1  |                |         "parts": [{"text": "Starting work on: Process this data"}]
receiver-1  |                |       }
receiver-1  |                |     }
receiver-1  |                |   }
receiver-1  |   2.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:03 +0000]
receiver-1  |                | Webhook received!
receiver-1  |   2.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:03 +0000]
receiver-1  |                |   Token: my-secret-token
receiver-1  |   2.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:03 +0000]
receiver-1  |                |   Payload: {
receiver-1  |                |     "taskId": "be85b851-...",
receiver-1  |                |     "status": {
receiver-1  |                |       "state": "TASK_STATE_WORKING",
receiver-1  |                |       "timestamp": "2025-05-01T12:00:03.000Z",
receiver-1  |                |       "message": {
receiver-1  |                |         "messageId": "...",
receiver-1  |                |         "role": "ROLE_AGENT",
receiver-1  |                |         "parts": [{"text": "Processing... 50% complete"}]
receiver-1  |                |       }
receiver-1  |                |     }
receiver-1  |                |   }
receiver-1  |   3.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:04 +0000]
receiver-1  |                | Webhook received!
receiver-1  |   3.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:04 +0000]
receiver-1  |                |   Token: my-secret-token
receiver-1  |   3.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:04 +0000]
receiver-1  |                |   Payload: {
receiver-1  |                |     "taskId": "be85b851-...",
receiver-1  |                |     "status": {
receiver-1  |                |       "state": "TASK_STATE_COMPLETED",
receiver-1  |                |       "timestamp": "2025-05-01T12:00:04.000Z"
receiver-1  |                |     }
receiver-1  |                |   }
```

You should see 3 webhook deliveries:
1. `TASK_STATE_WORKING` -- "Starting work on: Process this data"
2. `TASK_STATE_WORKING` -- "Processing... 50% complete"
3. `TASK_STATE_COMPLETED` -- work is done

Each webhook includes the `token` you provided (`my-secret-token`) in the `X-A2A-Notification-Token` header.

## Step 5: Poll for the final result

Replace `TASK_ID_HERE` with the `id` from Step 3:

```sh
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"GetTask","params":{"id":"TASK_ID_HERE"}}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "id": "be85b851-1234-5678-9abc-def012345678",
    "contextId": "a1b2c3d4-5678-9abc-def0-123456789abc",
    "status": {
      "state": "TASK_STATE_COMPLETED",
      "timestamp": "2025-05-01T12:00:04.000Z"
    },
    "artifacts": [
      {
        "artifactId": "...",
        "name": "result",
        "parts": [
          {
            "text": "Result for: Process this data\n\nProcessed successfully via webhook worker."
          }
        ]
      }
    ],
    "history": [
      {"messageId": "m1", "role": "ROLE_USER", "parts": [{"text": "Process this data"}]},
      {"messageId": "...", "role": "ROLE_AGENT", "parts": [{"text": "Starting work on: Process this data"}]},
      {"messageId": "...", "role": "ROLE_AGENT", "parts": [{"text": "Processing... 50% complete"}]},
      {"messageId": "...", "role": "ROLE_AGENT", "parts": [{"text": "Work complete."}]}
    ]
  }
}
```

## Step 6: Push notification config CRUD

The agent supports the full push notification config lifecycle. These operations use the `TASK_ID_HERE` from Step 3.

### Create a push notification config

```sh
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"CreateTaskPushNotificationConfig","params":{
    "taskId":"TASK_ID_HERE",
    "url":"http://receiver:9293/webhook",
    "token":"another-token"
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "id": "cfg-1234-5678-9abc-def012345678",
    "url": "http://receiver:9293/webhook",
    "token": "another-token"
  }
}
```

**Copy the config `id`** for the next steps.

### Get a specific push notification config

Replace `CONFIG_ID_HERE`:

```sh
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"GetTaskPushNotificationConfig","params":{
    "taskId":"TASK_ID_HERE",
    "id":"CONFIG_ID_HERE"
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "id": "cfg-1234-5678-9abc-def012345678",
    "url": "http://receiver:9293/webhook",
    "token": "another-token"
  }
}
```

### List all push notification configs for a task

```sh
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":5,"method":"ListTaskPushNotificationConfigs","params":{
    "taskId":"TASK_ID_HERE"
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "configs": [
      {
        "id": "cfg-0000-...",
        "url": "http://receiver:9293/webhook",
        "token": "my-secret-token"
      },
      {
        "id": "cfg-1234-...",
        "url": "http://receiver:9293/webhook",
        "token": "another-token"
      }
    ],
    "nextPageToken": ""
  }
}
```

### Delete a push notification config

```sh
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":6,"method":"DeleteTaskPushNotificationConfig","params":{
    "taskId":"TASK_ID_HERE",
    "id":"CONFIG_ID_HERE"
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": null
}
```

## Step 7: Cleanup

```sh
docker compose down
```

## Files

| File | Purpose |
|---|---|
| `agent/config.ru` | Agent -- async processing, push notification config CRUD, webhook delivery |
| `agent/falcon.rb` | Falcon config for agent (port 9292) |
| `agent/Gemfile` | Agent dependencies |
| `agent/Dockerfile` | Container build for the agent service |
| `receiver/config.ru` | Webhook receiver -- logs incoming POST payloads |
| `receiver/falcon.rb` | Falcon config for receiver (port 9293) |
| `receiver/Gemfile` | Receiver dependencies |
| `receiver/Dockerfile` | Container build for the receiver service |
| `docker-compose.yml` | Two-service compose config |

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/push-notifications)
