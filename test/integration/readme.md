# Integration Tests

Runs `A2A::Client` scripts against the full echo agent in Docker over both JSON-RPC and REST bindings.

## Run

```
test/integration/run
test/integration/run --build   # force rebuild
```

## Run Individual Scripts

```
docker compose -f test/integration/docker-compose.yml up -d --build
bundle exec ruby test/integration/json_rpc/send_message.rb
docker compose -f test/integration/docker-compose.yml down
```
