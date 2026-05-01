# Multi-Turn Conversation

Demonstrates the `INPUT_REQUIRED` state for multi-turn interactions where the agent asks for user confirmation before proceeding.

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/multi-turn)

## What you'll learn

- Task state transitions: `SUBMITTED` -> `WORKING` -> `INPUT_REQUIRED` -> `COMPLETED`
- Multi-turn conversation flow using `taskId` to continue a task
- Confirmation-gated processing (agent asks, user confirms)
- SQLite-backed persistent task store

## Step 1: Start the agent

```bash
git clone https://github.com/general-intelligence-systems/a2a.git
cd a2a/examples/multi-turn
docker compose up -d --build
```

Expected output:

```
[+] Building 12.3s (9/9) FINISHED
[+] Running 1/1
 ✔ Container multi-turn-agent-1  Started
```

## Step 2: Check the logs

```bash
docker compose logs
```

Expected output:

```
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Research Planner starting...
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Multi-turn example: INPUT_REQUIRED → confirmation → COMPLETED
```

## Step 3: Turn 1 -- Send a research topic

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Research quantum computing"}]}
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
        "state": "TASK_STATE_INPUT_REQUIRED",
        "timestamp": "2025-05-01T12:00:01.234Z",
        "message": {
          "messageId": "f7e6d5c4-3210-9876-fedc-ba9876543210",
          "role": "ROLE_AGENT",
          "parts": [
            {
              "text": "I've prepared a research plan for: Research quantum computing\n\nPlan:\n1. Survey existing literature\n2. Identify key themes and gaps\n3. Synthesize findings into a report\n\nSay 'go ahead' to proceed."
            }
          ]
        }
      },
      "history": [
        {
          "messageId": "m1",
          "role": "ROLE_USER",
          "parts": [{"text": "Research quantum computing"}]
        },
        {
          "messageId": "f7e6d5c4-3210-9876-fedc-ba9876543210",
          "role": "ROLE_AGENT",
          "parts": [
            {
              "text": "I've prepared a research plan for: Research quantum computing\n\nPlan:\n1. Survey existing literature\n2. Identify key themes and gaps\n3. Synthesize findings into a report\n\nSay 'go ahead' to proceed."
            }
          ]
        }
      ]
    }
  }
}
```

The key things to notice:
- The state is `TASK_STATE_INPUT_REQUIRED` -- the agent is waiting for your confirmation.
- The `task.id` field contains the task ID you'll need for Turn 2.

**Copy the `task.id` value from the response.** You'll need it in the next step.

## Step 4: Turn 2 -- Confirm the plan

Replace `TASK_ID_HERE` with the `id` from the Turn 1 response:

```bash
curl -s -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"SendMessage","params":{
    "message":{"messageId":"m2","role":"ROLE_USER","taskId":"TASK_ID_HERE","parts":[{"text":"go ahead"}]}
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "task": {
      "id": "be85b851-1234-5678-9abc-def012345678",
      "contextId": "a1b2c3d4-5678-9abc-def0-123456789abc",
      "status": {
        "state": "TASK_STATE_COMPLETED",
        "timestamp": "2025-05-01T12:00:05.678Z"
      },
      "artifacts": [
        {
          "artifactId": "c3d4e5f6-7890-1234-5678-9abcdef01234",
          "name": "research-report",
          "parts": [
            {
              "text": "Research Report: Research quantum computing\n\n1. Background: Research quantum computing is a rapidly evolving field.\n2. Key findings: Multiple approaches exist.\n3. Recommendations: Further investigation warranted.\n\n[This is a simulated research output]"
            }
          ]
        }
      ],
      "history": [
        {
          "messageId": "m1",
          "role": "ROLE_USER",
          "parts": [{"text": "Research quantum computing"}]
        },
        {
          "messageId": "f7e6d5c4-3210-9876-fedc-ba9876543210",
          "role": "ROLE_AGENT",
          "parts": [{"text": "I've prepared a research plan for: Research quantum computing\n\nPlan:\n1. Survey existing literature\n2. Identify key themes and gaps\n3. Synthesize findings into a report\n\nSay 'go ahead' to proceed."}]
        },
        {
          "messageId": "m2",
          "role": "ROLE_USER",
          "parts": [{"text": "go ahead"}]
        },
        {
          "messageId": "a1b2c3d4-0000-0000-0000-000000000000",
          "role": "ROLE_AGENT",
          "parts": [{"text": "Research complete. See the attached report."}]
        }
      ]
    }
  }
}
```

The key things to notice:
- The state is now `TASK_STATE_COMPLETED`.
- The `artifacts` array contains the research report.
- The `history` shows the full conversation: your topic, the agent's plan, your confirmation, and the agent's completion message.

## Step 5: Cleanup

```bash
docker compose down
```

## Files

| File | Purpose |
|---|---|
| `config.ru` | Agent logic -- SendMessage (new task + continuation), GetTask |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/multi-turn)
