# Multi-Agent Orchestration

Three A2A agents communicating via the protocol: an LLM-powered orchestrator discovers remote agents and delegates tasks to the most appropriate one.

## What it demonstrates

- Agent-to-agent communication via `A2A::Client`
- LLM-powered routing (Brute) to select the right agent for a request
- Agent card discovery at runtime
- Multi-service Docker Compose setup

## Architecture

| Service | Port | Role |
|---|---|---|
| **greeter** | 9292 | LLM-powered greeting generator |
| **translator** | 9293 | LLM-powered language translator |
| **host** | 9294 | Orchestrator -- discovers agents, routes requests via LLM |

The **host** agent discovers the greeter and translator agent cards at startup, then uses an LLM to decide which agent should handle each incoming request. It delegates via `A2A::Client.send_message` and returns the remote agent's response.

## Prerequisites

Requires an LLM API key. Set one of:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GEMINI_API_KEY`

## Running

### Directly

```sh
cd examples/multi-agent
bundle install

# Start all three agents in the background
cd greeter && bundle exec falcon serve --bind http://0.0.0.0:9292 &
cd ../translator && bundle exec falcon serve --bind http://0.0.0.0:9293 &
cd ../host && bundle exec falcon serve --bind http://0.0.0.0:9294 &
```

### With Docker (recommended)

```sh
ANTHROPIC_API_KEY=sk-... docker compose up --build
```

## Testing

Send a greeting request (routed to greeter):

```sh
curl -X POST http://localhost:9294/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Greet Alice for her birthday"}]}
  }}'
```

Send a translation request (routed to translator):

```sh
curl -X POST http://localhost:9294/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"SendMessage","params":{
    "message":{"messageId":"m2","role":"ROLE_USER","parts":[{"text":"Translate hello to Japanese"}]}
  }}'
```

## Files

| File | Purpose |
|---|---|
| `greeter/config.ru` | Greeter agent -- generates creative greetings via Brute |
| `translator/config.ru` | Translator agent -- translates text via Brute |
| `host/config.ru` | Host orchestrator -- discovers agents, routes via LLM |
| `*/falcon.rb` | Falcon server configs for each service |
| `Gemfile` | Shared dependencies (includes `brute` gem) |
| `Dockerfile` | Multi-service build using `SERVICE` arg |
| `docker-compose.yml` | Three-service compose config |
