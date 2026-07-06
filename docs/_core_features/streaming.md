---
layout: default
title: Streaming
nav_order: 4
description: This guide covers SSE streaming for real-time task updates and chunked
  artifact delivery.
---

# Streaming

This guide covers SSE streaming for real-time task updates and chunked artifact delivery.

## Opening a Stream

SSE streaming works natively with Falcon — no threads, no polling. Every request gets a stream builder at `env["a2a.stream"]`. Call `open` to start streaming; it auto-selects the right wire format (JSON-RPC or REST) for the current request, runs your block inside an Async fiber, and finishes the stream automatically when the block exits — even on exception.

```ruby
in "SendStreamingMessage"
  env["a2a.stream"].open(task_id: task_id, context_id: context_id) do |s|
    s.task(status: { state: "TASK_STATE_WORKING", timestamp: now })
    # ... do the work ...
    s.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: now })
  end
```

If you never call `open`, the request is handled as a normal (non-streaming) response.

## Typed Event Emitters

The stream exposes one method per `Stream Response` event type. Each builds a validated schema object and injects the stream's `task_id` and `context_id` automatically — you never pass them per event:

```ruby
s.task(status: { state: "TASK_STATE_WORKING" })

s.message(message_id: "m1", role: "ROLE_AGENT", parts: [{ text: "Hello" }])

s.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: now })

s.artifact_update(
  artifact:   { artifact_id: "a1", name: "output.txt", parts: [{ text: "..." }] },
  append:     false,
  last_chunk: true,
)
```

## Streaming Artifacts in Chunks

Chunk semantics: `append: false` creates the artifact, `append: true` extends it, `last_chunk: true` closes it. From the [streaming-artifacts example]({% link _examples/examples-streaming.md %}):

```ruby
in "SendStreamingMessage"
  env["a2a.stream"].open(task_id: task_id, context_id: context_id) do |s|
    s.task(status: { state: "TASK_STATE_WORKING", timestamp: now })

    artifact_id = SecureRandom.uuid

    chunks.each_with_index do |chunk_text, i|
      s.artifact_update(
        artifact: {
          artifact_id: artifact_id,
          name:        "output.txt",
          parts:       [{ text: chunk_text }],
        },
        append:     i > 0,
        last_chunk: i == chunks.length - 1,
      )
    end

    s.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: now })
  end
```

Status updates can be interleaved between artifact chunks to report progress.

## Subscribe to Task Updates

`SubscribeToTask` is just another operation — open a stream and relay whatever event source your app maintains (state management is your application's concern):

```ruby
in "SubscribeToTask"
  id   = env["a2a.request"].id
  task = TASKS[id] or raise A2A::TaskNotFoundError.new(id)

  env["a2a.stream"].open(task_id: id, context_id: task["contextId"]) do |s|
    # Initial snapshot
    s.task(status: task["status"])

    # Relay live events from your own pub/sub (e.g. an Async::Queue per task)
    while (event = SUBSCRIPTIONS[id].dequeue)
      s.status_update(status: event["status"])
      break if TERMINAL_STATES.include?(event.dig("status", "state"))
    end
  end
```

## Consuming a Stream from the Client

Streaming client methods take a block; each SSE event is parsed into a validated `Stream Response` object:

```ruby
client = A2A::Client.new("http://localhost:9292")

client.send_streaming_message(
  message: { message_id: "m1", role: "ROLE_USER", parts: [{ text: "Hello" }] }
) do |event|
  event.task            # set on task snapshot events
  event.status_update   # set on status update events
  event.artifact_update # set on artifact update events
  event.message         # set on message events
end
```
