---
layout: default
title: Streaming Artifacts
nav_order: 3
description: Demonstrates chunked artifact streaming with append/lastChunk semantics,
  streaming multiple files as separate artifacts over SSE.
---

# Streaming Artifacts

Demonstrates chunked artifact streaming with `append`/`lastChunk` semantics, streaming multiple files as separate artifacts over SSE.

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/streaming-artifacts)

## What you'll learn

- `SendStreamingMessage` with chunked artifact delivery
- Multiple artifacts per stream (one per generated file)
- Chunk semantics: `append: false` for first chunk, `append: true` for subsequent, `lastChunk: true` for final
- Interleaved status updates and artifact updates
- Non-streaming fallback via `SendMessage`
- Falcon-native SSE streaming (async fibers, no threads)

## Step 1: Start the agent

```bash
git clone https://github.com/general-intelligence-systems/a2a.git
cd a2a/examples/streaming-artifacts
docker compose up -d --build
```

Expected output:

```
[+] Building 12.3s (9/9) FINISHED
[+] Running 1/1
 ✔ Container streaming-artifacts-agent-1  Started
```

## Step 2: Check the logs

```bash
docker compose logs
```

Expected output:

```
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Code Generator starting...
agent-1  |   0.0s     info: main [pid=1] [2025-05-01 12:00:00 +0000]
agent-1  |                | Streaming artifacts example: chunked files with append/lastChunk
```

## Step 3: Stream generated code files (SSE)

```bash
curl -N -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"SendStreamingMessage","params":{
    "message":{"messageId":"m1","role":"ROLE_USER","parts":[{"text":"Generate a web app"}]}
  }}'
```

Expected output (SSE events arrive in real-time):

```
data: {"jsonrpc":"2.0","id":1,"result":{"task":{"id":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_WORKING","timestamp":"2025-05-01T12:00:01.000Z"}}}}

data: {"jsonrpc":"2.0","id":1,"result":{"artifactUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","artifact":{"artifactId":"aaa-111-...","name":"index.html","description":"Generated file: index.html","parts":[{"text":"<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n"}]},"append":false,"lastChunk":false}}}

data: {"jsonrpc":"2.0","id":1,"result":{"artifactUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","artifact":{"artifactId":"aaa-111-...","name":"index.html","description":"Generated file: index.html","parts":[{"text":"  <title>Generated App</title>\n  <link rel=\"stylesheet\" href=\"style.css\">\n</head>\n"}]},"append":true,"lastChunk":false}}}

data: {"jsonrpc":"2.0","id":1,"result":{"artifactUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","artifact":{"artifactId":"aaa-111-...","name":"index.html","description":"Generated file: index.html","parts":[{"text":"<body>\n  <div id=\"app\"></div>\n  <script src=\"app.js\"></script>\n</body>\n</html>"}]},"append":true,"lastChunk":true}}}

data: {"jsonrpc":"2.0","id":1,"result":{"statusUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_WORKING","timestamp":"...","message":{"messageId":"...","role":"ROLE_AGENT","parts":[{"text":"Generated index.html, working on next file..."}]}}}}}

data: {"jsonrpc":"2.0","id":1,"result":{"artifactUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","artifact":{"artifactId":"bbb-222-...","name":"style.css","description":"Generated file: style.css","parts":[{"text":"/* Generated styles */\n* { margin: 0; padding: 0; box-sizing: border-box; }\n\n"}]},"append":false,"lastChunk":false}}}

...more style.css chunks...

data: {"jsonrpc":"2.0","id":1,"result":{"statusUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_WORKING","timestamp":"...","message":{"messageId":"...","role":"ROLE_AGENT","parts":[{"text":"Generated style.css, working on next file..."}]}}}}}

...app.js chunks...

data: {"jsonrpc":"2.0","id":1,"result":{"statusUpdate":{"taskId":"be85b851-...","contextId":"a1b2c3d4-...","status":{"state":"TASK_STATE_COMPLETED","timestamp":"..."}}}}
```

Each file streams as a separate artifact with this chunk pattern:

```
artifactUpdate { append: false, lastChunk: false }   -- first chunk (creates the artifact)
artifactUpdate { append: true,  lastChunk: false }   -- middle chunks (append to artifact)
artifactUpdate { append: true,  lastChunk: true  }   -- final chunk (closes the artifact)
```

Status updates are interleaved between files to show progress.

Press `Ctrl+C` after the stream ends.

## Step 4: Non-streaming fallback (SendMessage)

```bash
curl -s -X POST http://localhost:9292/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"SendMessage","params":{
    "message":{"messageId":"m2","role":"ROLE_USER","parts":[{"text":"Generate a web app"}]}
  }}' | jq .
```

Expected output:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "task": {
      "id": "c4d5e6f7-8901-2345-6789-abcdef012345",
      "contextId": "b2c3d4e5-6789-0123-4567-89abcdef0123",
      "status": {
        "state": "TASK_STATE_COMPLETED",
        "timestamp": "2025-05-01T12:00:10.000Z"
      },
      "artifacts": [
        {
          "artifactId": "...",
          "name": "index.html",
          "parts": [{"text": "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <title>Generated App</title>\n  <link rel=\"stylesheet\" href=\"style.css\">\n</head>\n<body>\n  <div id=\"app\"></div>\n  <script src=\"app.js\"></script>\n</body>\n</html>"}]
        },
        {
          "artifactId": "...",
          "name": "style.css",
          "parts": [{"text": "/* Generated styles */\n* { margin: 0; padding: 0; box-sizing: border-box; }\n\nbody {\n  font-family: system-ui, sans-serif;\n  background: #f5f5f5;\n  color: #333;\n}\n\n#app {\n  max-width: 800px;\n  margin: 2rem auto;\n  padding: 1rem;\n  background: white;\n  border-radius: 8px;\n  box-shadow: 0 2px 4px rgba(0,0,0,0.1);\n}"}]
        },
        {
          "artifactId": "...",
          "name": "app.js",
          "parts": [{"text": "// Generated application\n'use strict';\n\nconst App = {\n  init() {\n    const el = document.getElementById('app');\n    el.innerHTML = '<h1>Hello, World!</h1><p>Generated by Code Generator Agent</p>';\n  }\n};\n\ndocument.addEventListener('DOMContentLoaded', () => App.init());"}]
        }
      ],
      "history": [
        {"messageId": "m2", "role": "ROLE_USER", "parts": [{"text": "Generate a web app"}]},
        {"messageId": "...", "role": "ROLE_AGENT", "parts": [{"text": "Generated 3 files: index.html, style.css, app.js"}]}
      ]
    }
  }
}
```

With `SendMessage`, all 3 files are generated synchronously and returned in a single response. No chunking, no SSE -- just the final result.

## Step 5: Cleanup

```bash
docker compose down
```

## Files

| File | Purpose |
|---|---|
| `config.ru` | Agent logic -- SendStreamingMessage (chunked), SendMessage (fallback), GetTask |
| `falcon.rb` | Falcon server config (binds to port 9292) |
| `Gemfile` | Dependencies |
| `Dockerfile` | Container build |
| `docker-compose.yml` | Single-service compose config |

[View source on GitHub](https://github.com/general-intelligence-systems/a2a/tree/main/examples/streaming-artifacts)
