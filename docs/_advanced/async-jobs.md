---
layout: default
title: Async Background Jobs
nav_order: 1
description: This guide covers non-blocking background work with returnImmediately
  and Store::Processor.
---

# Async Background Jobs

This guide covers non-blocking background work with `returnImmediately` and `Store::Processor`.

## Return Immediately

Use `Store::Processor` for non-blocking background work with `returnImmediately`:

```ruby
processor = A2A::Store::Processor.new

on "SendMessage" do |request|
  task_id = SecureRandom.uuid
  store.create(task_id, SecureRandom.uuid)

  return_immediately = request.configuration&.return_immediately

  work = proc do
    store.update_state(task_id, "TASK_STATE_WORKING")
    # ... long-running work ...
    store.complete(task_id, nil)
  end

  if return_immediately
    processor.call(&work)  # fire and forget
    task = store.get(task_id)
    respond A2A::Protocol::JsonSchema["Send Message Response"].new(
      task: { "id" => task_id, "status" => { "state" => "TASK_STATE_SUBMITTED" } }
    )
  else
    work.call  # blocking
    task = store.get(task_id)
    respond A2A::Protocol::JsonSchema["Send Message Response"].new(task: { ... })
  end
end
```

The client can then poll with `get_task` or subscribe with `subscribe_to_task` to track progress.
