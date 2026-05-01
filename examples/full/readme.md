# Full Echo Agent

Demonstrates all 11 A2A protocol operations in a single agent with Falcon-native SSE streaming and a SQLite-backed persistent task store.

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/full)

## What you'll learn

All 11 A2A operations:

1. **SendMessage** -- echo with task creation and continuation
2. **SendStreamingMessage** -- SSE streaming via `Protocol::HTTP::Body::Writable`
3. **GetTask** -- retrieve task by ID with optional history truncation
4. **ListTasks** -- paginated task listing with filters
5. **CancelTask** -- cancel in-progress tasks
6. **SubscribeToTask** -- real-time SSE updates via `Async::Queue` pub/sub
7. **CreateTaskPushNotificationConfig** -- register webhook configs
8. **GetTaskPushNotificationConfig** -- retrieve a specific config
9. **ListTaskPushNotificationConfigs** -- list all configs for a task
10. **DeleteTaskPushNotificationConfig** -- remove a config
11. **GetExtendedAgentCard** -- returns unsupported (demonstrates error handling)

Key features:
- Falcon-native SSE streaming (no threads, pure async fibers)
- SQLite-backed persistent task store
- Push notification config CRUD

## Step 1: Start the agent

```bash
git clone https://github.com/general-intelligence-systems/a2a.git
cd a2a/examples/full
docker compose up -d --build
```

Expected output:

```
[+] Building 12.3s (9/9) FINISHED
[+] Running 1/1
 ✔ Container full-agent-1  Started
```

## Step 2: Check the logs

```bash
docker compose logs
```

Expected output:

```
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Full Echo Agent starting...
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Agent card: Full Echo Agent
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Store: SQLite (echo_agent.db)
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Streaming: Falcon-native SSE via Protocol::HTTP::Body::Writable
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Concurrency: Async fibers (no threads)
```

## Step 3: Operation 1 -- SendMessage

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Hello, world!"}]}
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
        "state": "TASK_STATE_COMPLETED",
        "timestamp": "2025-05-01T12:00:01.234Z"
      },
      "artifacts": [
        {
          "artifactId": "d4e5f6a7-8901-2345-6789-abcdef012345",
          "name": "echo-response",
          "parts": [{"text": "Echo: Hello, world!"}]
        }
      ],
      "history": [
        {"messageId": "m1", "role": "ROLE_USER", "parts": [{"text": "Hello, world!"}]},
        {"messageId": "...", "role": "ROLE_AGENT", "parts": [{"text": "Echo: Hello, world!"}]}
      ]
    }
  }
}
```

**Copy the `task.id` value.** You'll need it for GetTask, CancelTask, SubscribeToTask, and push notification config steps.

## Step 4: Operation 1b -- SendMessage (continuation)

You can continue an existing task by providing `taskId` in the message. Replace `TASK_ID_HERE`:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"SendMessage","params":{
    "message":{"messageId":"m2","role":"ROLE_USER","taskId":"TASK_ID_HERE","parts":[{"text":"Follow-up message"}]}
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "error": {
    "code": -32004,
    "message": "Task is in a terminal state",
    "data": [
      {
        "@type": "type.googleapis.com/google.rpc.ErrorInfo",
        "reason": "UNSUPPORTED_OPERATION",
        "domain": "a2a-protocol.org"
      }
    ]
  }
}
```

This correctly errors because the task from Step 3 is already `COMPLETED` (a terminal state). You cannot continue a completed task.

## Step 5: Operation 2 -- SendStreamingMessage

```bash
curl -N -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"SendStreamingMessage","params":{
    "message":{"messageId":"m3","role":"ROLE_USER","parts":[{"text":"Stream this!"}]}
  }}'
```

Expected output (SSE events):

```
data: {"jsonrpc":"2.0","id":3,"result":{"task":{"id":"c4d5e6f7-...","contextId":"b3c4d5e6-...","status":{"state":"TASK_STATE_WORKING","timestamp":"2025-05-01T12:00:05.000Z"}}}}

data: {"jsonrpc":"2.0","id":3,"result":{"artifactUpdate":{"taskId":"c4d5e6f7-...","contextId":"b3c4d5e6-...","artifact":{"artifactId":"...","name":"echo-response","parts":[{"text":"Echo: Stream this!"}]},"append":false,"lastChunk":true}}}

data: {"jsonrpc":"2.0","id":3,"result":{"statusUpdate":{"taskId":"c4d5e6f7-...","contextId":"b3c4d5e6-...","status":{"state":"TASK_STATE_COMPLETED","timestamp":"2025-05-01T12:00:05.150Z"}}}}
```

Three SSE events:
1. Task snapshot with `TASK_STATE_WORKING`
2. Artifact update with the echo response (`append: false, lastChunk: true` -- single-chunk artifact)
3. Status update with `TASK_STATE_COMPLETED`

Press `Ctrl+C` after the stream ends.

## Step 6: Operation 3 -- GetTask

Retrieve a task by ID. Replace `TASK_ID_HERE` with the `id` from Step 3:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"GetTask","params":{"id":"TASK_ID_HERE"}}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "id": "be85b851-1234-5678-9abc-def012345678",
    "contextId": "a1b2c3d4-5678-9abc-def0-123456789abc",
    "status": {
      "state": "TASK_STATE_COMPLETED",
      "timestamp": "2025-05-01T12:00:01.234Z"
    },
    "artifacts": [
      {
        "artifactId": "d4e5f6a7-8901-2345-6789-abcdef012345",
        "name": "echo-response",
        "parts": [{"text": "Echo: Hello, world!"}]
      }
    ],
    "history": [
      {"messageId": "m1", "role": "ROLE_USER", "parts": [{"text": "Hello, world!"}]},
      {"messageId": "...", "role": "ROLE_AGENT", "parts": [{"text": "Echo: Hello, world!"}]}
    ]
  }
}
```

You can also truncate history with `historyLength`:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":5,"method":"GetTask","params":{"id":"TASK_ID_HERE","historyLength":1}}' | jq .
```

This returns only the last message in `history`.

## Step 7: Operation 4 -- ListTasks

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":6,"method":"ListTasks","params":{}}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "tasks": [
      {
        "id": "be85b851-...",
        "contextId": "a1b2c3d4-...",
        "status": {"state": "TASK_STATE_COMPLETED", "timestamp": "..."},
        "history": [
          {"messageId": "m1", "role": "ROLE_USER", "parts": [{"text": "Hello, world!"}]},
          {"messageId": "...", "role": "ROLE_AGENT", "parts": [{"text": "Echo: Hello, world!"}]}
        ]
      },
      {
        "id": "c4d5e6f7-...",
        "contextId": "b3c4d5e6-...",
        "status": {"state": "TASK_STATE_COMPLETED", "timestamp": "..."},
        "history": [
          {"messageId": "m3", "role": "ROLE_USER", "parts": [{"text": "Stream this!"}]},
          {"messageId": "...", "role": "ROLE_AGENT", "parts": [{"text": "Echo: Stream this!"}]}
        ]
      }
    ],
    "nextPageToken": "",
    "pageSize": 50,
    "totalSize": 2
  }
}
```

ListTasks supports pagination and filtering:

```bash
# Filter by state
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":7,"method":"ListTasks","params":{"status":"TASK_STATE_COMPLETED","pageSize":10}}' | jq .

# Include artifacts in the response
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":8,"method":"ListTasks","params":{"includeArtifacts":true}}' | jq .
```

## Step 8: Operation 5 -- CancelTask

First, create a new task to cancel (we need a non-terminal task, so let's create one via SendMessage and immediately try to cancel -- since this echo agent completes instantly, we'll see the expected error for canceling a completed task):

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":9,"method":"SendMessage","params":{
    "message":{"messageId":"m4","role":"ROLE_USER","parts":[{"text":"Cancel me"}]}
  }}' | jq -r '.result.task.id'
```

Copy the task ID, then attempt to cancel it (replace `TASK_ID_HERE`):

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":10,"method":"CancelTask","params":{"id":"TASK_ID_HERE"}}' | jq .
```

Expected output (the echo agent completes tasks instantly, so it's already terminal):

```json
{
  "jsonrpc": "2.0",
  "id": 10,
  "error": {
    "code": -32002,
    "message": "Task is not cancelable",
    "data": [
      {
        "@type": "type.googleapis.com/google.rpc.ErrorInfo",
        "reason": "TASK_NOT_CANCELABLE",
        "domain": "a2a-protocol.org",
        "metadata": {
          "taskId": "TASK_ID_HERE",
          "state": "TASK_STATE_COMPLETED"
        }
      }
    ]
  }
}
```

This correctly returns an error because the task is already completed. To see a successful cancellation, use the [async-jobs example](https://github.com/general-intelligence-systems/a2a/tree/main/examples/async-jobs) which has long-running tasks.

## Step 9: Operation 6 -- SubscribeToTask

SubscribeToTask requires a non-terminal task. Since this echo agent completes tasks instantly, subscribing to a completed task returns an error:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":11,"method":"SubscribeToTask","params":{"id":"TASK_ID_HERE"}}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 11,
  "error": {
    "code": -32004,
    "message": "Cannot subscribe to a task in a terminal state",
    "data": [
      {
        "@type": "type.googleapis.com/google.rpc.ErrorInfo",
        "reason": "UNSUPPORTED_OPERATION",
        "domain": "a2a-protocol.org",
        "metadata": {
          "taskId": "TASK_ID_HERE",
          "state": "TASK_STATE_COMPLETED"
        }
      }
    ]
  }
}
```

To see live SSE subscriptions in action, use the [async-jobs example](https://github.com/general-intelligence-systems/a2a/tree/main/examples/async-jobs).

## Step 10: Operation 7 -- CreateTaskPushNotificationConfig

Register a webhook config on an existing task. Replace `TASK_ID_HERE`:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":12,"method":"CreateTaskPushNotificationConfig","params":{
    "taskId":"TASK_ID_HERE",
    "url":"http://example.com/webhook",
    "token":"my-secret-token"
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 12,
  "result": {
    "id": "cfg-1234-5678-9abc-def012345678",
    "url": "http://example.com/webhook",
    "token": "my-secret-token"
  }
}
```

**Copy the config `id`** for the next steps.

## Step 11: Operation 8 -- GetTaskPushNotificationConfig

Retrieve a specific config. Replace `TASK_ID_HERE` and `CONFIG_ID_HERE`:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":13,"method":"GetTaskPushNotificationConfig","params":{
    "taskId":"TASK_ID_HERE",
    "id":"CONFIG_ID_HERE"
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 13,
  "result": {
    "id": "cfg-1234-5678-9abc-def012345678",
    "url": "http://example.com/webhook",
    "token": "my-secret-token"
  }
}
```

## Step 12: Operation 9 -- ListTaskPushNotificationConfigs

List all webhook configs for a task. Replace `TASK_ID_HERE`:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":14,"method":"ListTaskPushNotificationConfigs","params":{
    "taskId":"TASK_ID_HERE"
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 14,
  "result": {
    "configs": [
      {
        "id": "cfg-1234-5678-9abc-def012345678",
        "url": "http://example.com/webhook",
        "token": "my-secret-token"
      }
    ],
    "nextPageToken": ""
  }
}
```

## Step 13: Operation 10 -- DeleteTaskPushNotificationConfig

Remove a webhook config. Replace `TASK_ID_HERE` and `CONFIG_ID_HERE`:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":15,"method":"DeleteTaskPushNotificationConfig","params":{
    "taskId":"TASK_ID_HERE",
    "id":"CONFIG_ID_HERE"
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 15,
  "result": null
}
```

## Step 14: Operation 11 -- GetExtendedAgentCard

This agent declares `extendedAgentCard: false` in its capabilities. Calling this operation demonstrates proper error handling:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":16,"method":"GetExtendedAgentCard","params":{}}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 16,
  "error": {
    "code": -32004,
    "message": "Extended agent card is not supported",
    "data": [
      {
        "@type": "type.googleapis.com/google.rpc.ErrorInfo",
        "reason": "UNSUPPORTED_OPERATION",
        "domain": "a2a-protocol.org"
      }
    ]
  }
}
```

## Step 15: Cleanup

```bash
docker compose down
```

## Files

| File | Purpose |
|---|---|
| `config.ru` | All 11 operation handlers, agent card, store setup |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/full)
