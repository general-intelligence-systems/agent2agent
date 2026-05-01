# Async Jobs

Demonstrates non-blocking task processing with background fibers, live progress via SSE, and polling.

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/async-jobs)

## What you'll learn

- `SendMessage` with `returnImmediately: true` returning a `SUBMITTED` task instantly
- `A2A::Store::Processor` running jobs in background fibers
- `SubscribeToTask` relaying live progress updates via SSE
- `GetTask` polling for final results
- `CancelTask` for in-progress jobs
- SQLite-backed persistent task store

## Step 1: Start the agent

```bash
git clone https://github.com/general-intelligence-systems/a2a.git
cd a2a/examples/async-jobs
docker compose up -d --build
```

Expected output:

```
[+] Building 12.3s (9/9) FINISHED
[+] Running 1/1
 ✔ Container async-jobs-agent-1  Started
```

## Step 2: Check the logs

```bash
docker compose logs
```

Expected output:

```
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Slow Worker starting...
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Async jobs example: returnImmediately + SubscribeToTask + Processor
```

## Step 3: Submit a job (returns immediately)

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Analyze this dataset"}]},
    "configuration":{"returnImmediately":true}
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

The response comes back instantly with `TASK_STATE_SUBMITTED`. The work is running in a background fiber. **Copy the `task.id` value** -- you'll need it for the next steps.

## Step 4: Subscribe for live SSE updates

Replace `TASK_ID_HERE` with the `id` from Step 3:

```bash
curl -N -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"SubscribeToTask","params":{"id":"TASK_ID_HERE"}}'
```

Expected output (SSE events stream in real-time):

```
data: {"jsonrpc":"2.0","id":2,"result":{"task":{"id":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_WORKING","timestamp":"2025-05-01T12:00:01.500Z"},"artifacts":[]}}}

data: {"jsonrpc":"2.0","id":2,"result":{"statusUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_WORKING","timestamp":"2025-05-01T12:00:02.000Z","message":{"messageId":"...","role":"ROLE_AGENT","parts":[{"text":"Step 1/4: Loading data..."}]}}}}}

data: {"jsonrpc":"2.0","id":2,"result":{"statusUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_WORKING","timestamp":"2025-05-01T12:00:02.800Z","message":{"messageId":"...","role":"ROLE_AGENT","parts":[{"text":"Step 2/4: Running analysis..."}]}}}}}

data: {"jsonrpc":"2.0","id":2,"result":{"statusUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_WORKING","timestamp":"2025-05-01T12:00:03.400Z","message":{"messageId":"...","role":"ROLE_AGENT","parts":[{"text":"Step 3/4: Generating insights..."}]}}}}}

data: {"jsonrpc":"2.0","id":2,"result":{"statusUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_WORKING","timestamp":"2025-05-01T12:00:03.800Z","message":{"messageId":"...","role":"ROLE_AGENT","parts":[{"text":"Step 4/4: Compiling report..."}]}}}}}

data: {"jsonrpc":"2.0","id":2,"result":{"statusUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_COMPLETED","timestamp":"2025-05-01T12:00:04.200Z"}}}}
```

The SSE stream shows each of the 4 work steps as they happen, then the final `TASK_STATE_COMPLETED` event. The connection closes automatically when the task reaches a terminal state.

Press `Ctrl+C` if the stream has already ended.

## Step 5: Poll with GetTask

Alternatively (or after the fact), you can poll for the final result. Replace `TASK_ID_HERE`:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"GetTask","params":{"id":"TASK_ID_HERE"}}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "id": "be85b851-1234-5678-9abc-def012345678",
    "contextId": "a1b2c3d4-5678-9abc-def0-123456789abc",
    "status": {
      "state": "TASK_STATE_COMPLETED",
      "timestamp": "2025-05-01T12:00:04.200Z"
    },
    "artifacts": [
      {
        "artifactId": "d4e5f6a7-8901-2345-6789-abcdef012345",
        "name": "analysis-report",
        "parts": [
          {
            "text": "Analysis Report for: Analyze this dataset\n\nFindings:\n- Data processed: 1,247 records\n- Anomalies detected: 3\n- Confidence: 94.7%\n- Recommendation: Proceed with caution\n\n[Simulated analysis result]"
          }
        ]
      }
    ],
    "history": [
      {
        "messageId": "m1",
        "role": "ROLE_USER",
        "parts": [{"text": "Analyze this dataset"}]
      },
      {
        "messageId": "...",
        "role": "ROLE_AGENT",
        "parts": [{"text": "Step 1/4: Loading data..."}]
      },
      {
        "messageId": "...",
        "role": "ROLE_AGENT",
        "parts": [{"text": "Step 2/4: Running analysis..."}]
      },
      {
        "messageId": "...",
        "role": "ROLE_AGENT",
        "parts": [{"text": "Step 3/4: Generating insights..."}]
      },
      {
        "messageId": "...",
        "role": "ROLE_AGENT",
        "parts": [{"text": "Step 4/4: Compiling report..."}]
      },
      {
        "messageId": "...",
        "role": "ROLE_AGENT",
        "parts": [{"text": "Analysis complete. See the attached report."}]
      }
    ]
  }
}
```

## Step 6: Cancel a task (optional)

To test cancellation, submit a new job and cancel it before it finishes. Submit:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"SendMessage","params":{
    "message":{"messageId":"m2","role":"ROLE_USER","parts":[{"text":"Another analysis"}]},
    "configuration":{"returnImmediately":true}
  }}' | jq -r '.result.task.id'
```

This prints just the task ID. Immediately cancel it (replace `TASK_ID_HERE`):

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":5,"method":"CancelTask","params":{"id":"TASK_ID_HERE"}}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "id": "TASK_ID_HERE",
    "contextId": "...",
    "status": {
      "state": "TASK_STATE_CANCELED",
      "timestamp": "2025-05-01T12:00:10.000Z"
    },
    "artifacts": []
  }
}
```

## Step 7: Cleanup

```bash
docker compose down
```

## Files

| File | Purpose |
|---|---|
| `config.ru` | Agent logic -- SendMessage (blocking/non-blocking), SubscribeToTask, GetTask, CancelTask |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/async-jobs)
