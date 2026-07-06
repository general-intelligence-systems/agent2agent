---
layout: default
title: Push Notifications
nav_order: 4
description: Demonstrates asynchronous task processing with push notification config
  management (inline and CRUD) plus a webhook receiver service.
---

# Push Notifications

Demonstrates asynchronous task processing with push notification config management — inline via `SendMessage` and through the full config CRUD operations — alongside a webhook receiver service.

[View source on GitHub](https://github.com/general-intelligence-systems/agent2agent/tree/main/examples/push-notifications)

## What you'll learn

- Async background processing with an `Async` fiber (immediate `SUBMITTED` response)
- Accepting an inline push notification config via `SendMessage`'s `configuration`
- Full push notification config CRUD: Create, Get, List, Delete
- Two-service setup: agent + webhook receiver

## Architecture

| Service | Port | Role |
|---|---|---|
| **agent** | 9292 | Processes jobs asynchronously, stores push notification configs per task |
| **receiver** | 9293 | Minimal Rack app that logs webhook POSTs to `/webhook` (with `X-A2A-Notification-Token` support) |

The agent always returns immediately with `SUBMITTED` state; work runs in a background fiber. Push notification configs are stored per task — both inline configs from `SendMessage` and configs registered via the CRUD operations. The receiver is a ready-made target that logs any webhook payload POSTed to it; actually delivering webhooks on state transitions is application code (the library provides the config operations, not a delivery mechanism).

## Step 1: Start both services

```bash
git clone https://github.com/general-intelligence-systems/agent2agent.git
cd agent2agent/examples/push-notifications
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

```bash
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

Both services should be running. The receiver waits for webhook POSTs on port 9293.

## Step 3: Submit a job with an inline push notification config

```bash
curl -s -X POST http://localhost:9292/ \
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

The response returns immediately with `TASK_STATE_SUBMITTED` — the handler stored the inline config, spawned an `Async` fiber, and responded without waiting. The work is now running in the background. **Copy the `task.id` value** for later steps.

## Step 4: Poll for the final result

The background fiber transitions the task `SUBMITTED` → `WORKING` → `COMPLETED` over about 2 seconds. Wait a moment, then poll. Replace `TASK_ID_HERE` with the `id` from Step 3:

```bash
curl -s -X POST http://localhost:9292/ \
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

If you poll quickly enough you'll catch the task in `TASK_STATE_WORKING` with a partial history.

## Step 5: Push notification config CRUD

The agent supports the full push notification config lifecycle. These operations use the `TASK_ID_HERE` from Step 3.

### Create a push notification config

```bash
curl -s -X POST http://localhost:9292/ \
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

```bash
curl -s -X POST http://localhost:9292/ \
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

```bash
curl -s -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":5,"method":"ListTaskPushNotificationConfigs","params":{
    "taskId":"TASK_ID_HERE"
  }}' | jq .
```

Expected output (the inline config from Step 3 plus the one created above):

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "configs": [
      {
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

```bash
curl -s -X POST http://localhost:9292/ \
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

## Step 6: Try the receiver

The receiver logs any webhook POST it gets — the same shape your agent would send when wiring up delivery:

```bash
curl -s -X POST http://localhost:9293/webhook \
  -H "Content-Type: application/json" \
  -H "X-A2A-Notification-Token: my-secret-token" \
  -d '{"taskId":"be85b851-...","status":{"state":"TASK_STATE_COMPLETED"}}'
```

```bash
docker compose logs receiver
```

```
receiver-1  |   5.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:06 +0000]
receiver-1  |                | Webhook received!
receiver-1  |   5.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:06 +0000]
receiver-1  |                |   Token: my-secret-token
receiver-1  |   5.0s     info: WebhookReceiver [pid=1] [2025-05-01 12:00:06 +0000]
receiver-1  |                |   Payload: { ... }
```

To deliver notifications from your own agent, POST the task status to each stored config's `url` (setting the config's `token` as the `X-A2A-Notification-Token` header) whenever the background fiber transitions state.

## Step 7: Cleanup

```bash
docker compose down
```

## Files

| File | Purpose |
|---|---|
| `agent/config.ru` | Agent -- async processing, push notification config CRUD |
| `agent/falcon.rb` | Falcon config for agent (port 9292) |
| `agent/Gemfile` | Agent dependencies |
| `agent/Dockerfile` | Container build for the agent service |
| `receiver/config.ru` | Webhook receiver -- logs incoming POST payloads |
| `receiver/falcon.rb` | Falcon config for receiver (port 9293) |
| `receiver/Gemfile` | Receiver dependencies |
| `receiver/Dockerfile` | Container build for the receiver service |
| `docker-compose.yml` | Two-service compose config |

[View source on GitHub](https://github.com/general-intelligence-systems/agent2agent/tree/main/examples/push-notifications)
