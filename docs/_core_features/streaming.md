---
layout: default
title: Streaming
nav_order: 4
description: This guide covers SSE streaming for real-time task updates and chunked
  artifact delivery.
---

# Streaming

This guide covers SSE streaming for real-time task updates and chunked artifact delivery.

## Streaming Artifacts

SSE streaming works natively with Falcon -- no threads, no polling. The `stream` helper auto-selects the right format based on the protocol binding.

```ruby
on "SendStreamingMessage" do |request|
  task_id = SecureRandom.uuid
  store.create(task_id, SecureRandom.uuid)
  s = stream

  Async do
    # Status update
    s.event({
      "task" => {
        "id"     => task_id,
        "status" => { "state" => "TASK_STATE_WORKING" },
      },
    })

    # Stream artifacts in chunks
    s.event({
      "artifactUpdate" => {
        "taskId"   => task_id,
        "artifact" => { "artifactId" => "a1", "name" => "output.txt",
                        "parts" => [{ "text" => "chunk 1..." }] },
        "append"    => false,
        "lastChunk" => false,
      },
    })

    s.event({
      "artifactUpdate" => {
        "taskId"   => task_id,
        "artifact" => { "artifactId" => "a1",
                        "parts" => [{ "text" => "chunk 2..." }] },
        "append"    => true,
        "lastChunk" => true,
      },
    })

    # Complete
    s.event({
      "statusUpdate" => {
        "taskId" => task_id,
        "status" => { "state" => "TASK_STATE_COMPLETED" },
      },
    })

    s.finish
  end
end
```

## Subscribe to Task Updates

Relay live updates from the store's pub/sub to an SSE stream:

```ruby
on "SubscribeToTask" do |request|
  task = store.get(request.id)
  sub_queue = store.subscribe(request.id)
  s = stream

  Async do
    # Initial snapshot
    s.event({ "task" => { "id" => task[:id], "status" => { "state" => task[:state] } } })

    # Relay live events
    while (event = sub_queue.dequeue)
      case event[:type]
      when :status  then s.event({ "statusUpdate" => event[:data] })
      when :artifact then s.event({ "artifactUpdate" => event[:data] })
      end

      state = event[:data].dig("status", "state")
      break if A2A::Store::SQLite::TERMINAL_STATES.include?(state)
    end

    s.finish
    store.unsubscribe(request.id, sub_queue)
  end
end
```
