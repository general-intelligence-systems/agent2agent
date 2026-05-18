# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "faraday"
require "async/http/faraday"
require "console"

module A2A
  # Faraday-based A2A protocol client.
  #
  # Supports both protocol bindings: JSON-RPC 2.0 and HTTP+JSON/REST.
  # Uses the async-http-faraday adapter for fiber-based non-blocking I/O
  # and supports SSE streaming for long-lived connections.
  #
  # Request params are validated against the operation's request schema
  # before sending. Responses are returned as Schema::Definition objects.
  #
  #   # JSON-RPC (default)
  #   client = A2A::Client.new("http://localhost:9292")
  #
  #   # REST
  #   client = A2A::Client.new("http://localhost:9292", binding: :rest)
  #
  class Client
    def initialize(url, binding: :json_rpc, &block)
      @url     = url.chomp("/")
      @binding = binding
      @conn    = build_connection(&block)
    end

    # GET /.well-known/agent-card.json
    #
    # Returns an A2A::Schema["Agent Card"] instance.
    def agent_card
      response = @conn.get("/.well-known/agent-card.json")
      parsed = response.body
      A2A::Schema["Agent Card"].new(parsed)
    end

    # Operations — each maps to a Proto operation name.
    Proto.operations.each do |op|
      method_name = op.name.gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, "")

      if op.server_streaming?
        define_method(method_name) do |params = {}, &block|
          Console.info(self) { "Client #{op.name}: #{params}" }
          invoke_streaming(op, params, &block)
        end
      else
        define_method(method_name) do |params = {}|
          Console.info(self) { "Client #{op.name}: #{params}" }
          invoke(op, params)
        end
      end
    end

    private

      def build_connection(&block)
        case @binding
        when :json_rpc then build_json_rpc_connection(&block)
        when :rest     then build_rest_connection(&block)
        else raise ArgumentError, "Unknown binding: #{@binding}"
        end
      end

      def build_json_rpc_connection(&block)
        ::Faraday.new(url: @url) do |f|
          f.request :a2a_schema
          f.request :a2a_json_rpc
          f.request :json

          f.response :a2a_json_rpc
          f.response :json

          f.adapter :async_http

          block&.call(f)
        end
      end

      def build_rest_connection(&block)
        ::Faraday.new(url: @url) do |f|
          f.request :a2a_schema
          f.request :a2a_rest
          f.request :json

          f.response :a2a_rest
          f.response :json

          f.adapter :async_http

          block&.call(f)
        end
      end

      def invoke(operation, params)
        request = operation.request_schema.new(params)
        request.valid!

        response = @conn.post("/") do |req|
          req.options.context = { a2a_operation: operation }
          req.body = request
        end

        response.body
      end

      def invoke_streaming(operation, params, &block)
        request = operation.request_schema.new(params)
        request.valid!

        @conn.post("/") do |req|
          req.options.context = { a2a_operation: operation }
          req.body = request
          req.headers["Accept"] = "text/event-stream"

          if block
            req.options.on_data = proc do |chunk, _size, env|
              block.call(chunk, env)
            end
          end
        end
      end
  end
end

test do
  # --- JSON-RPC binding (default) ---

  it "generates methods for all Proto operations" do
    client = A2A::Client.new("http://localhost:9292") do |f|
      f.adapter :test do |stub|
        stub.post("/a2a") { |env|
          [200, { "content-type" => "application/json" }, JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "result" => {} })]
        }
      end
    end

    expected = %w[
      send_message
      send_streaming_message
      get_task
      list_tasks
      cancel_task
      subscribe_to_task
      create_task_push_notification_config
      get_task_push_notification_config
      list_task_push_notification_configs
      delete_task_push_notification_config
      get_extended_agent_card
    ]

    expected.each do |name|
      client.respond_to?(name).should == true
    end
  end

  it "agent_card returns a Schema object" do
    client = A2A::Client.new("http://localhost:9292") do |f|
      f.adapter :test do |stub|
        stub.get("/.well-known/agent-card.json") { |env|
          [200, { "content-type" => "application/json" }, JSON.generate({
            "name" => "Test Agent",
            "version" => "1.0.0",
            "capabilities" => { "streaming" => true }
          })]
        }
      end
    end

    card = client.agent_card
    card.should.be.kind_of(A2A::Schema::Definition)
    card.name.should == "Test Agent"
    card.version.should == "1.0.0"
  end

  it "json_rpc: send_message validates, wraps in JSON-RPC, returns Schema" do
    client = A2A::Client.new("http://localhost:9292") do |f|
      f.adapter :test do |stub|
        stub.post("/a2a") { |env|
          parsed = JSON.parse(env.body)
          parsed["method"].should == "SendMessage"
          parsed["params"]["message"]["role"].should == "ROLE_USER"

          [200, { "content-type" => "application/json" }, JSON.generate({
            "jsonrpc" => "2.0", "id" => parsed["id"],
            "result" => {
              "task" => {
                "id" => "task-1",
                "contextId" => "ctx-1",
                "status" => { "state" => "TASK_STATE_COMPLETED" },
                "artifacts" => [{
                  "artifactId" => "a-1",
                  "parts" => [{ "text" => "Echo: Hello" }]
                }]
              }
            }
          })]
        }
      end
    end

    result = client.send_message(
      message_id: "msg-1",
      role: "ROLE_USER",
      parts: [{ text: "Hello" }]
    )
    result.should.be.kind_of(A2A::Schema::Definition)
  end

  it "json_rpc: get_task returns a Task" do
    client = A2A::Client.new("http://localhost:9292") do |f|
      f.adapter :test do |stub|
        stub.post("/a2a") { |env|
          parsed = JSON.parse(env.body)
          parsed["method"].should == "GetTask"
          parsed["params"]["id"].should == "task-123"

          [200, { "content-type" => "application/json" }, JSON.generate({
            "jsonrpc" => "2.0", "id" => parsed["id"],
            "result" => {
              "id" => "task-123",
              "contextId" => "ctx-456",
              "status" => {
                "state" => "TASK_STATE_SUBMITTED"
              }
            }
          })]
        }
      end
    end

    result = client.get_task("task-123")
    result.should.be.kind_of(A2A::Schema::Definition)
    result.id.should == "task-123"
    result.context_id.should == "ctx-456"
  end

  it "json_rpc: raises on JSON-RPC error" do
    client = A2A::Client.new("http://localhost:9292") do |f|
      f.adapter :test do |stub|
        stub.post("/a2a") { |env|
          [200, { "content-type" => "application/json" }, JSON.generate({
            "jsonrpc" => "2.0",
            "id" => 1,
            "error" => {
              "code" => -32600,
              "message" => "Invalid Request"
            }
          })]
        }
      end
    end

    lambda { client.get_task("task-123") }.should.raise(RuntimeError)
  end

  it "json_rpc: raises ValidationError on invalid params" do
    client = A2A::Client.new("http://localhost:9292") do |f|
      f.adapter :test do |stub|
        stub.post("/a2a") { |env| [200, { "content-type" => "application/json" }, "{}"] }
      end
    end

    lambda { client.send_message("not_a_hash") }.should.raise(A2A::Schema::ValidationError)
  end

  it "json_rpc: send_streaming_message sends correct method and Accept header" do
    captured_env = nil
    client = A2A::Client.new("http://localhost:9292") do |f|
      f.adapter :test do |stub|
        stub.post("/a2a") { |env|
          captured_env = env
          [200, { "content-type" => "text/event-stream" }, ""]
        }
      end
    end

    client.send_streaming_message(
      message_id: "msg-1",
      role: "ROLE_USER",
      parts: [{ text: "Hello" }]
    ) do |chunk, env|
    end

    parsed = JSON.parse(captured_env.request_body)
    parsed["method"].should == "SendStreamingMessage"
    captured_env.request_headers["Accept"].should == "text/event-stream"
  end

  # --- REST binding ---

  it "rest: send_message posts to /message:send with application/a2a+json" do
    captured_env = nil
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.post("/message:send") { |env|
          captured_env = env
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({
            "task" => {
              "id" => "task-1",
              "contextId" => "ctx-1",
              "status" => {
                "state" => "TASK_STATE_COMPLETED"
              }
            }
          })]
        }
      end
    end

    result = client.send_message(
      message_id: "msg-1",
      role: "ROLE_USER",
      parts: [{ text: "Hello" }]
    )
    result.should.be.kind_of(A2A::Schema::Definition)
    captured_env.request_headers["content-type"].should == "application/a2a+json"
  end

  it "rest: get_task uses GET /tasks/{id}" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.get("/tasks/task-123") { |env|
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({
            "id" => "task-123",
            "contextId" => "ctx-456",
            "status" => {
              "state" => "TASK_STATE_SUBMITTED"
            }
          })]
        }
      end
    end

    result = client.get_task(id: "task-123")
    result.should.be.kind_of(A2A::Schema::Definition)
    result.id.should == "task-123"
  end

  it "rest: list_tasks uses GET /tasks" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.get("/tasks") { |env|
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({
            "tasks" => [
              { "id" => "t-1", "contextId" => "c-1", "status" => { "state" => "TASK_STATE_COMPLETED" } }
            ]
          })]
        }
      end
    end

    result = client.list_tasks
    result.should.be.kind_of(A2A::Schema::Definition)
  end

  it "rest: cancel_task uses POST /tasks/{id}:cancel" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.post("/tasks/task-123:cancel") { |env|
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({
            "id" => "task-123", "contextId" => "ctx-456",
            "status" => { "state" => "TASK_STATE_CANCELED" }
          })]
        }
      end
    end

    result = client.cancel_task("task-123")
    result.should.be.kind_of(A2A::Schema::Definition)
    result.id.should == "task-123"
  end

  it "rest: create_task_push_notification_config uses POST /tasks/{task_id}/pushNotificationConfigs" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.post("/tasks/task-123/pushNotificationConfigs") { |env|
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({
            "id" => "config-1", "taskId" => "task-123",
            "url" => "https://example.com/webhook"
          })]
        }
      end
    end

    result = client.create_task_push_notification_config(
      task_id: "task-123", url: "https://example.com/webhook"
    )
    result.should.be.kind_of(A2A::Schema::Definition)
  end

  it "rest: get_task_push_notification_config uses GET /tasks/{task_id}/pushNotificationConfigs/{id}" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.get("/tasks/task-123/pushNotificationConfigs/config-1") { |env|
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({
            "id" => "config-1", "taskId" => "task-123",
            "url" => "https://example.com/webhook"
          })]
        }
      end
    end

    result = client.get_task_push_notification_config(id: "config-1", task_id: "task-123")
    result.should.be.kind_of(A2A::Schema::Definition)
  end

  it "rest: list_task_push_notification_configs uses GET /tasks/{task_id}/pushNotificationConfigs" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.get("/tasks/task-123/pushNotificationConfigs") { |env|
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({
            "pushNotificationConfigs" => []
          })]
        }
      end
    end

    result = client.list_task_push_notification_configs(task_id: "task-123")
    result.should.be.kind_of(A2A::Schema::Definition)
  end

  it "rest: delete_task_push_notification_config uses DELETE /tasks/{task_id}/pushNotificationConfigs/{id}" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.delete("/tasks/task-123/pushNotificationConfigs/config-1") { |env|
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({})]
        }
      end
    end

    result = client.delete_task_push_notification_config(id: "config-1", task_id: "task-123")
    result.should == {}
  end

  it "rest: get_extended_agent_card uses GET /extendedAgentCard" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.get("/extendedAgentCard") { |env|
          [200, { "content-type" => "application/a2a+json" }, JSON.generate({
            "name" => "Extended Agent",
            "version" => "2.0.0",
            "capabilities" => {
              "streaming" => true,
              "extendedAgentCard" => true
            }
          })]
        }
      end
    end

    result = client.get_extended_agent_card
    result.should.be.kind_of(A2A::Schema::Definition)
    result.name.should == "Extended Agent"
  end

  it "rest: subscribe_to_task uses GET /tasks/{id}:subscribe with Accept header" do
    captured_env = nil
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.get("/tasks/task-1:subscribe") { |env|
          captured_env = env
          [200, { "content-type" => "text/event-stream" }, ""]
        }
      end
    end

    client.subscribe_to_task("task-1") do |chunk, env|
    end

    captured_env.request_headers["Accept"].should == "text/event-stream"
  end

  it "rest: raises on HTTP 400 error" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.get("/tasks/bad-id") { |env|
          [400, { "content-type" => "application/problem+json" }, JSON.generate({
            "type" => "error",
            "title" => "Bad Request","status" => 400
          })]
        }
      end
    end

    lambda { client.get_task(id: "bad-id") }.should.raise(RuntimeError)
  end

  it "rest: raises ValidationError on invalid params" do
    client = A2A::Client.new("http://localhost:9292", binding: :rest) do |f|
      f.adapter :test do |stub|
        stub.post("/message:send") { |env| [200, { "content-type" => "application/a2a+json" }, "{}"] }
      end
    end

    lambda { client.send_message("not_a_hash") }.should.raise(A2A::Schema::ValidationError)
  end
end
