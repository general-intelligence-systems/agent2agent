---
layout: default
title: Full Echo Agent
nav_order: 6
description: The most complete example agent -- task lifecycle, Falcon-native SSE
  streaming, history truncation, pagination, cancellation, and error handling.
---

# Full Echo Agent

The most complete example agent: task lifecycle, Falcon-native SSE streaming, history truncation, pagination, cancellation, and error handling — all in one pattern-matching handler backed by an in-memory task hash.

[View source on GitHub](https://github.com/general-intelligence-systems/agent2agent/tree/main/examples/full)

## What you'll learn

The operations this agent handles:

1. **SendMessage** -- echo with task creation and continuation guard
2. **SendStreamingMessage** -- SSE streaming via `env["a2a.stream"]`
3. **GetTask** -- retrieve task by ID with history truncation (`env["a2a.history_length"]`)
4. **ListTasks** -- paginated task listing with filters (`env["a2a.page_size"]`)
5. **CancelTask** -- cancel in-progress tasks, with `TaskNotCancelableError` for terminal ones

Key features:
- Falcon-native SSE streaming (no threads, pure async fibers)
- In-memory task state guarded by `Async::Semaphore`
- Server caps: `A2A.agent(agent_card: card, history_length: 20, page_size: 50)`
- Unhandled operations automatically answer with `UnsupportedOperationError` (`-32004`)

## Step 1: Start the agent

```bash
git clone https://github.com/general-intelligence-systems/agent2agent.git
cd agent2agent/examples/full
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
agent-1  |                | Store: in-memory (Async::Semaphore)
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Streaming: Falcon-native SSE via Protocol::HTTP::Body::Writable
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Concurrency: Async fibers (no threads)
```

## Step 3: SendMessage

```bash
curl -s -X POST http://localhost:9292/ \
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

**Copy the `task.id` value.** You'll need it for GetTask and CancelTask.

## Step 4: SendMessage (continuation)

You can continue an existing task by providing `taskId` in the message. Replace `TASK_ID_HERE`:

```bash
curl -s -X POST http://localhost:9292/ \
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

This correctly errors because the task from Step 3 is already `COMPLETED` (a terminal state). You cannot continue a completed task. For a working continuation flow, see the [multi-turn example]({% link _examples/examples-multi-turn.md %}).

## Step 5: SendStreamingMessage

```bash
curl -N -X POST http://localhost:9292/ \
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

## Step 6: GetTask

Retrieve a task by ID. Replace `TASK_ID_HERE` with the `id` from Step 3:

```bash
curl -s -X POST http://localhost:9292/ \
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

You can also truncate history with `historyLength` (the server clamps it to its own `history_length: 20` cap):

```bash
curl -s -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":5,"method":"GetTask","params":{"id":"TASK_ID_HERE","historyLength":1}}' | jq .
```

This returns only the last message in `history`.

## Step 7: ListTasks

```bash
curl -s -X POST http://localhost:9292/ \
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
curl -s -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":7,"method":"ListTasks","params":{"status":"TASK_STATE_COMPLETED","pageSize":10}}' | jq .

# Include artifacts in the response
curl -s -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":8,"method":"ListTasks","params":{"includeArtifacts":true}}' | jq .
```

## Step 8: CancelTask

Create a new task to cancel (since this echo agent completes instantly, we'll see the expected error for canceling a completed task):

```bash
curl -s -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":9,"method":"SendMessage","params":{
    "message":{"messageId":"m4","role":"ROLE_USER","parts":[{"text":"Cancel me"}]}
  }}' | jq -r '.result.task.id'
```

Copy the task ID, then attempt to cancel it (replace `TASK_ID_HERE`):

```bash
curl -s -X POST http://localhost:9292/ \
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

The handler raises `A2A::TaskNotCancelableError` for terminal tasks — the server formats it into this spec-compliant response. To see a successful cancellation, cancel a long-running task like those in the [push notifications example]({% link _examples/examples-push-notifications.md %}).

## Step 9: Unhandled operations

The handler's `case ... in` doesn't match every operation — anything unmatched automatically becomes an `UnsupportedOperationError`:

```bash
curl -s -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":11,"method":"GetExtendedAgentCard","params":{}}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 11,
  "error": {
    "code": -32004,
    "message": "Operation not supported: GetExtendedAgentCard",
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

No `else` branch needed — the server converts the pattern-match miss into this error. `SubscribeToTask` and the push notification config operations respond the same way for this agent; see the [push notifications example]({% link _examples/examples-push-notifications.md %}) for an agent that handles the config CRUD operations.

## Step 10: Cleanup

```bash
docker compose down
```

## Files

| File | Purpose |
|---|---|
| `config.ru` | The handler block -- all operations, agent card, in-memory task state |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |

[View source on GitHub](https://github.com/general-intelligence-systems/agent2agent/tree/main/examples/full)
