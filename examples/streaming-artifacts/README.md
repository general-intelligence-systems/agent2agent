# Streaming Artifacts

Demonstrates chunked artifact streaming with `append`/`lastChunk` semantics, streaming multiple files as separate artifacts over SSE.

## What it demonstrates

- `SendStreamingMessage` with chunked artifact delivery
- Multiple artifacts per stream (one per generated file)
- Chunk semantics: `append: false` for first chunk, `append: true` for subsequent, `lastChunk: true` for final
- Interleaved status updates and artifact updates
- Non-streaming fallback via `SendMessage`
- Falcon-native SSE streaming (async fibers, no threads)

## Running

```sh
cd examples/streaming-artifacts
bundle install
bundle exec falcon serve --bind http://0.0.0.0:9292
```

Or with Docker:

```sh
docker compose up --build
```

## Testing

Stream generated code files (SSE):

```sh
curl -N -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendStreamingMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Generate a web app"}]}
  }}'
```

Non-streaming fallback:

```sh
curl -X POST http://localhost:9292/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Generate a web app"}]}
  }}'
```

## How it works

The agent simulates generating 3 code files (`index.html`, `style.css`, `app.js`). Each file is streamed as a separate artifact in multiple chunks:

```
artifactUpdate { append: false, lastChunk: false }  -- first chunk
artifactUpdate { append: true,  lastChunk: false }  -- middle chunks
artifactUpdate { append: true,  lastChunk: true  }  -- final chunk
```

Status updates are interleaved between files to show progress.

## Files

| File | Purpose |
|---|---|
| `config.ru` | Agent logic -- SendStreamingMessage (chunked), SendMessage (fallback), GetTask |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |
