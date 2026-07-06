---
layout: default
title: Managing Task State
nav_order: 2
description: This guide covers managing task state in your agent — the gem ships no
  built-in task store, so persistence is your application's concern.
---

# Managing Task State

The gem ships **no built-in task store**. The handler block is plain Ruby: how tasks are created, updated, and persisted is entirely your application's concern. This keeps the library small and lets you use whatever fits — an in-memory hash for demos, your existing database for production.

## In-Memory (development)

The runnable examples use a plain hash guarded by an `Async::Semaphore`. Falcon serves requests on fibers, so a semaphore is enough to keep multi-step mutations atomic — no threads, no mutex:

```ruby
require "async/semaphore"

TASKS = {}
LOCK  = Async::Semaphore.new(1)
NOW   = -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ") }
TERMINAL_STATES = %w[TASK_STATE_COMPLETED TASK_STATE_CANCELLED TASK_STATE_FAILED].freeze

run A2A.agent(agent_card: agent_card) do |env|
  case env["a2a.operation"]
  in "SendMessage"
    task_id = SecureRandom.uuid

    LOCK.acquire do
      TASKS[task_id] = {
        id: task_id, context_id: SecureRandom.uuid,
        state: "TASK_STATE_SUBMITTED", updated_at: NOW.(),
        artifacts: [], history: [],
      }
    end

    # ... do the work, then build the response from the stored task ...

  in "GetTask"
    id    = env["a2a.request"].id
    limit = env["a2a.history_length"]

    task = LOCK.acquire { TASKS[id] }
    raise A2A::TaskNotFoundError.new(id) unless task

    A2A::Protocol::JsonSchema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { state: task[:state], timestamp: task[:updated_at] },
      artifacts:  task[:artifacts],
      history:    task[:history]&.last(limit),
    )

  in "CancelTask"
    id   = env["a2a.request"].id
    task = LOCK.acquire { TASKS[id] }
    raise A2A::TaskNotFoundError.new(id) unless task
    raise A2A::TaskNotCancelableError.new(id, state: task[:state]) if TERMINAL_STATES.include?(task[:state])

    LOCK.acquire do
      TASKS[id][:state] = "TASK_STATE_CANCELLED"
      TASKS[id][:updated_at] = NOW.()
    end
    # ... return the Task ...
  end
end
```

Note how the middleware-provided limits plug in: `env["a2a.history_length"]` caps the history you return, and `env["a2a.page_size"]` drives `ListTasks` pagination. See the [full example]({% link _examples/examples-full.md %}) for a complete implementation including `ListTasks` with pagination.

## Your Own Database (production)

For durable state, back the handler with your own models. Because the handler is just a block, this is ordinary application code:

```ruby
run A2A.agent(agent_card: agent_card) do |env|
  case env["a2a.operation"]
  in "GetTask"
    task = Task.find_by(id: env["a2a.request"].id)
    raise A2A::TaskNotFoundError.new(env["a2a.request"].id) unless task

    task.to_a2a  # your method that builds A2A::Protocol::JsonSchema["Task"]
  end
end
```

Whatever the backend, the contract is the same: return a `Schema::Definition` (build it with `A2A::Protocol::JsonSchema[...]`) and raise `A2A::Error` subclasses like `A2A::TaskNotFoundError` when lookups fail.
