# Async Jobs

Demonstrates non-blocking task processing with background fibers, live progress via SSE, and polling.

## What it demonstrates

- `SendMessage` with `returnImmediately: true` returning a `SUBMITTED` task instantly
- `A2A::Store::Processor` running jobs in background fibers
- `SubscribeToTask` relaying live progress updates via SSE
- `GetTask` polling for final results
- `CancelTask` for in-progress jobs
- SQLite-backed persistent task store

## Running

```sh
cd examples/async-jobs
bundle install
bundle exec falcon serve --bind http://0.0.0.0:9292
```

Or with Docker:

```sh
docker compose up --build
```

## Testing

### 1. Submit a job (returns immediately with SUBMITTED)

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Analyze this dataset"}]},
    "configuration":{"returnImmediately":true}
  }}'
```

### 2. Subscribe for live updates (SSE stream)

```sh
curl -N -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"SubscribeToTask","params":{"id":"TASK_ID_HERE"}}'
```

### 3. Or poll for the result

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"GetTask","params":{"id":"TASK_ID_HERE"}}'
```

## How it works

The agent simulates a 4-step analysis pipeline with delays between steps. In non-blocking mode (`returnImmediately: true`), the work runs in a background fiber via `A2A::Store::Processor` while the response returns immediately. Clients can then either subscribe for real-time SSE updates or poll with `GetTask`.

## Files

| File | Purpose |
|---|---|
| `config.ru` | Agent logic -- SendMessage (blocking/non-blocking), SubscribeToTask, GetTask, CancelTask |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |
