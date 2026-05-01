# Multi-Turn Conversations

This guide covers using `TASK_STATE_INPUT_REQUIRED` to build confirmation-gated and multi-step conversations.

## Input Required

Use `TASK_STATE_INPUT_REQUIRED` to pause execution and wait for user input:

```ruby
on "SendMessage" do |request|
  text = extract_text.(request.message)
  task_id = request.message.task_id

  if task_id
    # Continuation -- user is responding
    if text.downcase.include?("go ahead")
      store.update_state(task_id, "TASK_STATE_WORKING")
      # ... do the work ...
      store.complete(task_id, nil)
    else
      # Re-ask
      store.update_state(task_id, "TASK_STATE_INPUT_REQUIRED",
        message: { "role" => "ROLE_AGENT",
                   "parts" => [{ "text" => "Please confirm." }] })
    end
  else
    # New task -- ask for confirmation
    task_id = SecureRandom.uuid
    store.create(task_id, SecureRandom.uuid)
    store.update_state(task_id, "TASK_STATE_INPUT_REQUIRED",
      message: { "role" => "ROLE_AGENT",
                 "parts" => [{ "text" => "Here's my plan. Say 'go ahead' to proceed." }] })
  end

  task = store.get(task_id)
  respond A2A::Schema["Send Message Response"].new(task: { ... })
end
```
