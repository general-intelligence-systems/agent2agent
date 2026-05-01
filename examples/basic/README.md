# Echo Agent

A minimal A2A agent that echoes messages back. This is the simplest starting point for understanding the A2A protocol.

## What it demonstrates

- Agent card discovery via `/.well-known/agent-card.json`
- `SendMessage` and `GetTask` operations
- Basic `A2A::Server` and `A2A::Agent` setup with Rack

## Running

```sh
cd examples/basic
bundle install
bundle exec falcon serve --bind http://0.0.0.0:9292
```

Or with Docker:

```sh
docker compose up --build
```

## Testing

Fetch the agent card:

```sh
curl http://localhost:9292/.well-known/agent-card.json
```

Send a message:

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{}}'
```

## Files

| File | Purpose |
|---|---|
| `config.ru` | Rack entry point -- defines the agent card, handlers, and boots the server |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |
