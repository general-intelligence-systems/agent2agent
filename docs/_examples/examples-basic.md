---
layout: default
title: Echo Agent
nav_order: 1
description: A minimal A2A agent that echoes messages back. The simplest starting
  point for understanding the A2A protocol.
---

# Echo Agent

A minimal A2A agent that echoes messages back. The simplest starting point for understanding the A2A protocol.

[View source on GitHub](https://github.com/general-intelligence-systems/agent2agent/tree/main/examples/basic)

## What you'll learn

- Agent card discovery via `/.well-known/agent-card.json`
- `SendMessage` and `GetTask` operations
- The minimal `A2A.agent` pattern-matching handler with Rack

## Step 1: Start the agent

```bash
git clone https://github.com/general-intelligence-systems/agent2agent.git
cd agent2agent/examples/basic
docker compose up -d --build
```

Expected output:

```
[+] Building 12.3s (9/9) FINISHED
[+] Running 1/1
 ✔ Container basic-agent-1  Started
```

## Step 2: Check the logs

```bash
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

```bash
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

```bash
curl -X POST http://localhost:9292/ \
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

This is a bare-bones echo agent -- it returns an empty response object. See the [full example](https://github.com/general-intelligence-systems/agent2agent/tree/main/examples/full) for a complete implementation with task state, streaming, pagination, and cancellation.

## Step 5: Cleanup

```bash
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

[View source on GitHub](https://github.com/general-intelligence-systems/agent2agent/tree/main/examples/basic)
