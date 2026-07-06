---
layout: default
title: Async Background Jobs
nav_order: 1
description: This guide covers non-blocking background work with Async fibers and
  immediate SUBMITTED responses.
---

# Async Background Jobs

This guide covers non-blocking background work — return a `SUBMITTED` task immediately and run the work in an [Async](https://github.com/socketry/async) fiber.

## Return Immediately

The server runs on Falcon's fiber scheduler, so `Async do ... end` inside a handler spawns a background fiber without threads. Store the task first, kick off the work, and respond right away:

```ruby
require "async"

in "SendMessage"
  text    = env["a2a.message"]
  task_id = SecureRandom.uuid

  TASKS[task_id] = {
    id: task_id, context_id: SecureRandom.uuid,
    state: "TASK_STATE_SUBMITTED", artifacts: [],
  }

  # Process in background
  Async do
    TASKS[task_id][:state] = "TASK_STATE_WORKING"

    # ... long-running work ...

    TASKS[task_id][:artifacts] << {
      "artifactId" => SecureRandom.uuid,
      "parts"      => [{ "text" => "Result for: #{text}" }],
    }
    TASKS[task_id][:state] = "TASK_STATE_COMPLETED"
  end

  # Return immediately with SUBMITTED state
  A2A::Protocol::JsonSchema["Send Message Response"].new(
    task: {
      "id"        => task_id,
      "contextId" => TASKS[task_id][:context_id],
      "status"    => { "state" => "TASK_STATE_SUBMITTED" },
    }
  )
```

The client can then poll with `get_task` to track progress, or — if you implement `SubscribeToTask` — follow live updates over SSE (see [Streaming]({% link _core_features/streaming.md %})).

Since fibers only yield at I/O points, guard multi-step mutations of shared state with an `Async::Semaphore` when several requests may touch the same task — see [Managing Task State]({% link _advanced/task-stores.md %}).

For a complete runnable version — including push notification config CRUD alongside the background processing — see the [push notifications example]({% link _examples/examples-push-notifications.md %}).
