# Echo Agent

A minimal A2A agent that echoes messages back. The simplest starting point for understanding the A2A protocol.

## What you'll learn

- Agent card discovery via `/.well-known/agent-card.json`
- `SendMessage` and `GetTask` operations
- Basic `A2A::Server` and `A2A::Agent` setup with Rack

## Step 1: Start the agent

```sh
cd examples/basic
docker compose up -d --build
```

Expected output:

```
[+] Building 12.3s (9/9) FINISHED
[+] Running 1/1
 ✔ Container basic-agent-1  Started
```

## Step 2: Check the logs

```sh
docker compose logs
```

Expected output:

```
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Echo Agent starting...
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Agent card: Echo Agent
agent-1  |   0.01s     info: Falcon::Controller [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Starting Falcon Host ...
```

## Step 3: Fetch the agent card

```sh
curl http://localhost:9292/.well-known/agent-card.json
```

Expected output:

```json
{
  "name": "Echo Agent",
  "description": "A simple echo agent that repeats your message.",
  "url": "http://localhost:9292",
  "version": "1.0.0"
}
```

## Step 4: Send a message

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{}}'
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {}
}
```

This is a bare-bones echo agent -- it returns an empty response object. See the [full example](../full/) for a complete implementation with all 11 operations.

## Step 5: Cleanup

```sh
docker compose down
```

## Files

| File | Purpose |
|---|---|
| `config.ru` | Rack entry point -- defines the agent card, handlers, and boots the server |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |
