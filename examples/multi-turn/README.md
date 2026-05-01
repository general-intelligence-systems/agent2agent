# Multi-Turn Conversation

Demonstrates the `INPUT_REQUIRED` state for multi-turn interactions where the agent asks for user confirmation before proceeding.

## What it demonstrates

- Task state transitions: `SUBMITTED` -> `WORKING` -> `INPUT_REQUIRED` -> `COMPLETED`
- Multi-turn conversation flow using `taskId` to continue a task
- Confirmation-gated processing (agent asks, user confirms)
- SQLite-backed persistent task store

## Running

```sh
cd examples/multi-turn
bundle install
bundle exec falcon serve --bind http://0.0.0.0:9292
```

Or with Docker:

```sh
docker compose up --build
```

## Testing

### Turn 1: Start a research task

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Research quantum computing"}]}
  }}'
```

The response includes the task ID and an `INPUT_REQUIRED` state with the agent's research plan:

```json
{"jsonrpc":"2.0","id":1,"result":{"task":{"id":"abc-123-...","contextId":"...","status":{"state":"TASK_STATE_INPUT_REQUIRED","timestamp":"..."}, ...}}}
```

### Turn 2: Confirm (use the taskId from turn 1)

> [!WARNING]
> Replace `TASK_ID_HERE` below with the `id` from the Turn 1 response.

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"SendMessage","params":{
    "message":{"messageId":"m2","role":"ROLE_USER","taskId":"TASK_ID_HERE","parts":[{"text":"go ahead"}]}
  }}'
```

The agent completes the research and returns a report artifact.

## How it works

1. **New task** (no `taskId`): The agent creates a task, generates a research plan, and transitions to `INPUT_REQUIRED` with a confirmation prompt.
2. **Continuation** (`taskId` present): The agent checks if the user confirmed (looks for "go ahead", "yes", or "confirm"). If confirmed, it completes the research. Otherwise, it re-asks.

## Files

| File | Purpose |
|---|---|
| `config.ru` | Agent logic -- SendMessage (new task + continuation), GetTask |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |
