# frozen_string_literal: true

# Executable proof of the documentation: runs every server snippet and client
# call from docs/_core_features/protocol-operations.md and error-handling.md
# against a live agent over both bindings (all 11 operations + error paths).
#
# Run with: bundle exec ruby test/docs_test.rb

ENV["CONSOLE_LEVEL"] ||= "warn"

require "a2a"
require "a2a/server/sse"
require "async"
require "async/semaphore"
require "async/http/server"
require "async/http/endpoint"
require "protocol/rack"
require "securerandom"
require "socket"

TASKS = {}
LOCK  = Async::Semaphore.new(1)
NOW   = -> { Time.now.utc.iso8601(3) }
TERMINAL_STATES = %w[TASK_STATE_COMPLETED TASK_STATE_CANCELLED TASK_STATE_FAILED].freeze
EXTENDED_CARD = { "name" => "Docs Agent (extended)", "version" => "1.0.0" }.freeze

AGENT = A2A.agent(agent_card: { "name" => "Docs Agent" }, history_length: 20, page_size: 50) do |env|
  case env["a2a.operation"]
  in "SendMessage"
    text = env["a2a.message"]
    msg  = env["a2a.request"].message

    if text.to_s.strip.empty?
      raise A2A::InvalidParamsError.new("message must contain non-empty text", fields: ["message.parts"])
    end

    if msg.task_id && !msg.task_id.to_s.empty? && TERMINAL_STATES.include?(TASKS.dig(msg.task_id, :state))
      raise A2A::UnsupportedOperationError.new(message: "Task is in a terminal state")
    end

    task_id = SecureRandom.uuid
    state = text == "slow" ? "TASK_STATE_WORKING" : "TASK_STATE_COMPLETED"

    task = LOCK.acquire do
      TASKS[task_id] = {
        id: task_id, context_id: msg.context_id.to_s.empty? ? SecureRandom.uuid : msg.context_id,
        state: state, updated_at: NOW.(),
        artifacts: [{ "artifactId" => SecureRandom.uuid, "parts" => [{ "text" => "Echo: #{text}" }] }],
        history: [], push_configs: [],
      }
    end

    A2A::Protocol::JsonSchema["Send Message Response"].new(
      task: {
        "id"        => task[:id],
        "contextId" => task[:context_id],
        "status"    => { "state" => task[:state], "timestamp" => task[:updated_at] },
        "artifacts" => task[:artifacts],
      }
    )

  in "SendStreamingMessage"
    task_id    = SecureRandom.uuid
    context_id = SecureRandom.uuid

    env["a2a.stream"].open(task_id: task_id, context_id: context_id) do |s|
      s.task(status: { state: "TASK_STATE_WORKING", timestamp: NOW.() })
      s.artifact_update(
        artifact: { artifact_id: "a-1", parts: [{ text: "Echo: #{env["a2a.message"]}" }] },
        append: false, last_chunk: true,
      )
      s.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: NOW.() })
    end

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

  in "ListTasks"
    request   = env["a2a.request"]
    page_size = env["a2a.page_size"]

    all = LOCK.acquire do
      TASKS.values.select do |t|
        (request.context_id.to_s.empty? || t[:context_id] == request.context_id) &&
        (request.status.to_s.empty?     || t[:state] == request.status)
      end
    end

    if !request.page_token.to_s.empty?
      idx = all.index { |t| t[:id] == request.page_token }
      all = idx ? all[(idx + 1)..] : []
    end

    page = all.first(page_size)
    next_token = page.size == page_size && page.size < all.size ? page.last[:id] : ""

    A2A::Protocol::JsonSchema["List Tasks Response"].new(
      tasks: page.map { |t|
        { "id" => t[:id], "contextId" => t[:context_id],
          "status" => { "state" => t[:state], "timestamp" => t[:updated_at] } }
      },
      next_page_token: next_token,
      page_size:       page_size,
      total_size:      all.size,
    )

  in "CancelTask"
    id   = env["a2a.request"].id
    task = LOCK.acquire { TASKS[id] }

    raise A2A::TaskNotFoundError.new(id) unless task
    raise A2A::TaskNotCancelableError.new(id, state: task[:state]) if TERMINAL_STATES.include?(task[:state])

    task = LOCK.acquire do
      TASKS[id][:state] = "TASK_STATE_CANCELLED"
      TASKS[id][:updated_at] = NOW.()
      TASKS[id]
    end

    A2A::Protocol::JsonSchema["Task"].new(
      id:         task[:id],
      context_id: task[:context_id],
      status:     { state: task[:state], timestamp: task[:updated_at] },
    )

  in "SubscribeToTask"
    id   = env["a2a.request"].id
    task = LOCK.acquire { TASKS[id] }
    raise A2A::TaskNotFoundError.new(id) unless task

    env["a2a.stream"].open(task_id: id, context_id: task[:context_id]) do |s|
      s.task(status: { state: task[:state], timestamp: task[:updated_at] })

      until TERMINAL_STATES.include?(TASKS[id][:state])
        sleep 0.1
      end
      s.status_update(status: { state: TASKS[id][:state], timestamp: TASKS[id][:updated_at] })
    end

  in "CreateTaskPushNotificationConfig"
    request = env["a2a.request"]
    task    = LOCK.acquire { TASKS[request.task_id] }
    raise A2A::TaskNotFoundError.new(request.task_id) unless task

    config = request.to_h
    config.delete("taskId")
    config["id"] ||= SecureRandom.uuid

    LOCK.acquire { task[:push_configs] << config }

    A2A::Protocol::JsonSchema["Task Push Notification Config"].new(config)

  in "GetTaskPushNotificationConfig"
    request = env["a2a.request"]
    task    = LOCK.acquire { TASKS[request.task_id] }
    raise A2A::TaskNotFoundError.new(request.task_id) unless task

    config = task[:push_configs].find { |c| c["id"] == request.id }
    unless config
      raise A2A::Internal::Errors::PushNotificationConfigNotFoundError.new(request.task_id, request.id)
    end

    A2A::Protocol::JsonSchema["Task Push Notification Config"].new(config)

  in "ListTaskPushNotificationConfigs"
    request = env["a2a.request"]
    task    = LOCK.acquire { TASKS[request.task_id] }
    raise A2A::TaskNotFoundError.new(request.task_id) unless task

    A2A::Protocol::JsonSchema["List Task Push Notification Configs Response"].new(
      configs:         task[:push_configs],
      next_page_token: "",
    )

  in "DeleteTaskPushNotificationConfig"
    request = env["a2a.request"]
    task    = LOCK.acquire { TASKS[request.task_id] }
    raise A2A::TaskNotFoundError.new(request.task_id) unless task

    LOCK.acquire { task[:push_configs].reject! { |c| c["id"] == request.id } }
    nil

  in "GetExtendedAgentCard"
    raise A2A::ExtendedAgentCardNotConfiguredError.new unless EXTENDED_CARD

    A2A::Protocol::JsonSchema["Agent Card"].new(EXTENDED_CARD)
  end
end

$failures = []
def check(name)
  yield
  puts "  ok  #{name}"
rescue StandardError => e
  $failures << [name, e]
  puts "  FAIL #{name}: #{e.class}: #{e.message}"
end

def assert(cond, msg = "assertion failed")
  raise msg unless cond
end

MESSAGE = { message_id: "msg-1", role: "ROLE_USER", parts: [{ text: "hello" }] }.freeze

Sync do
  socket = TCPServer.new("127.0.0.1", 0)
  port = socket.addr[1]
  socket.close

  endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{port}")
  adapter = Protocol::Rack::Adapter.new(AGENT)
  server_task = Async { Async::HTTP::Server.new(adapter, endpoint).run }

  begin
    %i[json_rpc rest].each do |binding|
      puts "== #{binding} =="
      client = A2A::Client.new("http://127.0.0.1:#{port}", binding: binding)
      err_class = binding == :json_rpc ? A2A::JsonRpcError : A2A::RestError

      check("agent_card") { assert client.agent_card.name == "Docs Agent" }

      task_id = nil
      check("send_message") do
        r = client.send_message(message: MESSAGE)
        task_id = r.task.id
        assert r.task.status.state == "TASK_STATE_COMPLETED"
        assert r.task.artifacts.first.parts.first.text == "Echo: hello"
      end

      check("send_message -> InvalidParamsError -32602") do
        client.send_message(message: { message_id: "m", role: "ROLE_USER", parts: [{ text: "  " }] })
        assert false, "no error raised"
      rescue err_class => e
        expected = binding == :json_rpc ? -32602 : 400
        assert e.code == expected, "code was #{e.code}"
        assert e.error_data&.first&.dig("reason") == "INVALID_PARAMS", "data: #{e.error_data.inspect}"
      end

      check("send_message continuation of terminal task -> UnsupportedOperationError -32004") do
        client.send_message(message: MESSAGE.merge(task_id: task_id))
        assert false, "no error raised"
      rescue err_class => e
        expected = binding == :json_rpc ? -32004 : 400
        assert e.code == expected, "code was #{e.code}"
      end

      check("send_streaming_message") do
        events = []
        client.send_streaming_message(message: MESSAGE) { |ev| events << ev }
        assert events.size == 3, "got #{events.size} events"
        assert events[1].artifact_update.artifact.parts.first.text == "Echo: hello"
        assert events.last.status_update.status.state == "TASK_STATE_COMPLETED"
      end

      check("get_task") do
        t = client.get_task(id: task_id, history_length: 5)
        assert t.id == task_id
        assert t.status.state == "TASK_STATE_COMPLETED"
      end

      check("get_task -> TaskNotFoundError -32001/404") do
        client.get_task(id: "no-such-task")
        assert false, "no error raised"
      rescue err_class => e
        expected = binding == :json_rpc ? -32001 : 404
        assert e.code == expected, "code was #{e.code}"
        assert e.error_data&.first&.dig("reason") == "TASK_NOT_FOUND"
        assert e.error_data&.first&.dig("metadata", "taskId") == "no-such-task"
      end

      check("list_tasks with pagination") do
        client.send_message(message: MESSAGE.merge(message_id: "msg-2")) # ensure >= 2 tasks
        r = client.list_tasks(page_size: 1)
        assert r.tasks.size == 1
        assert !r.next_page_token.to_s.empty?
        r2 = client.list_tasks(page_size: 1, page_token: r.next_page_token)
        assert r2.tasks.first.id != r.tasks.first.id
      end

      slow_id = nil
      check("cancel_task") do
        slow_id = client.send_message(message: MESSAGE.merge(parts: [{ text: "slow" }])).task.id
        t = client.cancel_task(id: slow_id)
        assert t.status.state == "TASK_STATE_CANCELLED"
      end

      check("cancel_task -> TaskNotCancelableError -32002") do
        client.cancel_task(id: slow_id)
        assert false, "no error raised"
      rescue err_class => e
        expected = binding == :json_rpc ? -32002 : 400
        assert e.code == expected, "code was #{e.code}"
        assert e.error_data&.first&.dig("reason") == "TASK_NOT_CANCELABLE"
      end

      check("subscribe_to_task") do
        events = []
        client.subscribe_to_task(id: task_id) { |ev| events << ev }
        assert events.size == 2, "got #{events.size} events"
        assert events.first.task.status.state == "TASK_STATE_COMPLETED"
      end

      config_id = nil
      check("create_task_push_notification_config") do
        c = client.create_task_push_notification_config(
          task_id: task_id, url: "https://example.com/webhook", token: "shared-secret"
        )
        config_id = c.id
        assert !config_id.to_s.empty?
        assert c.url == "https://example.com/webhook"
      end

      check("get_task_push_notification_config") do
        c = client.get_task_push_notification_config(id: config_id, task_id: task_id)
        assert c.url == "https://example.com/webhook"
        assert c.token == "shared-secret"
      end

      check("list_task_push_notification_configs") do
        r = client.list_task_push_notification_configs(task_id: task_id)
        assert r.configs.map(&:url).include?("https://example.com/webhook")
      end

      check("delete_task_push_notification_config") do
        client.delete_task_push_notification_config(id: config_id, task_id: task_id)
      end

      check("get deleted config -> PushNotificationConfigNotFoundError -32001/404") do
        client.get_task_push_notification_config(id: config_id, task_id: task_id)
        assert false, "no error raised"
      rescue err_class => e
        expected = binding == :json_rpc ? -32001 : 404
        assert e.code == expected, "code was #{e.code}"
      end

      check("get_extended_agent_card") do
        assert client.get_extended_agent_card.name == "Docs Agent (extended)"
      end
    end
  ensure
    server_task.stop
  end
end

puts
if $failures.empty?
  puts "ALL CHECKS PASSED"
else
  puts "#{$failures.size} FAILURES"
  exit 1
end
