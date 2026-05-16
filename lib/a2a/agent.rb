# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  # DSL wrapper that collects operation handlers for an A2A agent.
  #
  # An Agent produces handler objects that conform to the Dispatcher's
  # duck-type contract (#operations, #call). Register an agent on a
  # Server the same way you would register a plain handler.
  #
  #   agent = A2A::Agent.new do
  #     on "SendMessage" do |request|
  #       respond A2A::Schema["Send Message Response"].new({})
  #     end
  #
  #     on "GetTask" do |request|
  #       task = store.get(request.id)
  #       respond A2A::Schema["Task"].new(task.to_h)
  #     end
  #   end
  #
  #   server.register(agent)
  #
  class Agent
    attr_reader :handlers

    def initialize(&block)
      @handlers = []

      instance_eval(&block) if block
    end

    # Register a handler block for one or more A2A operations.
    #
    # Operations are identified by their proto name (e.g. "SendMessage",
    # "GetTask", "CancelTask"). See A2A::Proto.operations for the full list.
    #
    def on(*operations, &block)
      raise ArgumentError, "on requires at least one operation" if operations.empty?
      raise ArgumentError, "on requires a block" unless block

      handler = Handler.new(
        agent:      self,
        operations: operations.flatten,
        block:      block
      )

      @handlers << handler
      handler
    end

    # Internal handler object produced by the #on DSL method.
    # Conforms to the Dispatcher duck-type: #operations, #call.
    class Handler
      attr_reader :operations

      def initialize(agent:, operations:, block:)
        @agent      = agent
        @operations = operations
        @block      = block
      end

      def call(env)
        result = Context.new(env).execute(&@block)

        # Return-value semantics: if the block returned a Schema object,
        # use it as the result (unless a stream was set up).
        if result.is_a?(A2A::Schema::Definition) && !env["a2a.stream"]
          env["a2a.result"] = result
        end

      rescue A2A::TaskNotFoundError => e
        env["a2a.error"] = e.to_h

      rescue A2A::TaskNotCancelableError => e
        env["a2a.error"] = e.to_h

      rescue A2A::UnsupportedOperationError => e
        env["a2a.error"] = e.to_h

      rescue A2A::InvalidParamsError => e
        env["a2a.error"] = e.to_h

      rescue A2A::PushNotificationConfigNotFoundError => e
        env["a2a.error"] = e.to_h
      end
    end

    # Execution context for handler blocks.
    # Provides helper methods so blocks can call store, respond, stream, etc.
    # directly without holding a reference to the env hash.
    class Context
      def initialize(env)
        @env = env
      end

      def execute(&block)
        instance_exec(@env["a2a.request"], &block)
      end

      def store
        @env["a2a.store"]
      end

      def request
        @env["a2a.request"]
      end

      def agent_card
        @env["a2a.agent_card"]
      end

      def respond(result)
        @env["a2a.result"] = result
      end

      # Create an SSE stream for streaming responses.
      #
      # Automatically selects the right stream type based on the binding:
      #   - JSON-RPC binding -> JsonRpcStream (wraps events in envelopes)
      #   - REST binding     -> RestStream (bare JSON events)
      #
      # The stream is registered on env["a2a.stream"] so the binding
      # middleware returns it as the Rack body. Falcon streams it natively
      # via Protocol::HTTP::Body::Writable — no threads, no polling.
      #
      # Usage in a handler block:
      #
      #   on "SendStreamingMessage" do |request|
      #     s = stream
      #     Async do
      #       s.event({ "task" => { ... } })
      #       s.event({ "statusUpdate" => { ... } })
      #       s.finish
      #     end
      #   end
      #
      def stream
        require "a2a/sse"

        s = if @env["a2a.json_rpc_id"]
          A2A::SSE::JsonRpcStream.new(json_rpc_id: @env["a2a.json_rpc_id"])
        else
          A2A::SSE::RestStream.new
        end

        @env["a2a.stream"] = s
        s
      end
    end
  end
end

test do
  describe "A2A::Agent" do
    it "registers handlers via the on DSL" do
      agent = A2A::Agent.new do
        on "SendMessage" do |request|
          # no-op
        end
      end

      agent.handlers.length.should == 1
      agent.handlers.first.operations.should == ["SendMessage"]
    end

    it "registers multiple operations on a single handler" do
      agent = A2A::Agent.new do
        on "SendMessage", "GetTask" do |request|
          # no-op
        end
      end

      agent.handlers.first.operations.should == ["SendMessage", "GetTask"]
    end

    it "raises if on is called without operations" do
      lambda {
        A2A::Agent.new do
          on do |request|; end
        end
      }.should.raise(ArgumentError)
    end

    it "raises if on is called without a block" do
      lambda {
        agent = A2A::Agent.new
        agent.on "SendMessage"
      }.should.raise(ArgumentError)
    end

    it "executes handler block in Context with access to env" do
      agent = A2A::Agent.new do
        on "SendMessage" do |request|
          respond({ "echo" => true })
        end
      end

      env = {
        "a2a.store"      => A2A::TaskStore.new,
        "a2a.request"    => { "message" => "hello" },
        "a2a.agent_card" => { "name" => "Test" },
      }

      agent.handlers.first.call(env)

      env["a2a.result"].should == { "echo" => true }
    end

    it "provides store access in handler context" do
      store = A2A::TaskStore.new
      seen_store = nil

      agent = A2A::Agent.new do
        on "SendMessage" do |request|
          seen_store = store
        end
      end

      env = { "a2a.store" => store, "a2a.request" => {} }
      agent.handlers.first.call(env)

      seen_store.should == store
    end

    it "creates a JsonRpcStream when JSON-RPC binding is active" do
      agent = A2A::Agent.new do
        on "SendStreamingMessage" do |request|
          s = stream
          s.is_a?(A2A::SSE::JsonRpcStream).should == true
        end
      end

      env = {
        "a2a.store"       => A2A::TaskStore.new,
        "a2a.request"     => {},
        "a2a.json_rpc_id" => 42,
      }
      agent.handlers.first.call(env)

      env["a2a.stream"].should.not.be.nil
      env["a2a.stream"].is_a?(Protocol::HTTP::Body::Readable).should == true
    end

    it "creates a RestStream when REST binding is active" do
      agent = A2A::Agent.new do
        on "SendStreamingMessage" do |request|
          s = stream
          s.is_a?(A2A::SSE::RestStream).should == true
        end
      end

      env = {
        "a2a.store"   => A2A::TaskStore.new,
        "a2a.request" => {},
      }
      agent.handlers.first.call(env)

      env["a2a.stream"].should.not.be.nil
    end

    # ── Return-value semantics ──────────────────────────────────────────

    it "captures a Schema::Definition return value as the result" do
      schema_obj = A2A::Schema["Task"].new(
        "id"        => "t-1",
        "contextId" => "c-1",
        "status"    => { "state" => "TASK_STATE_COMPLETED", "timestamp" => "2025-01-01T00:00:00.000Z" },
      )

      agent = A2A::Agent.new do
        on "GetTask" do |request|
          schema_obj
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.result"].should == schema_obj
    end

    it "does not override result when stream is set" do
      agent = A2A::Agent.new do
        on "SendStreamingMessage" do |request|
          s = stream
          A2A::Schema["Task"].new(
            "id" => "t-1", "contextId" => "c-1",
            "status" => { "state" => "TASK_STATE_COMPLETED", "timestamp" => "2025-01-01T00:00:00.000Z" },
          )
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.result"].should.be.nil
      env["a2a.stream"].should.not.be.nil
    end

    it "ignores non-Schema return values" do
      agent = A2A::Agent.new do
        on "SendMessage" do |request|
          { "raw" => "hash" }
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.result"].should.be.nil
    end

    it "respond still works for backward compatibility" do
      agent = A2A::Agent.new do
        on "SendMessage" do |request|
          respond({ "echo" => true })
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.result"].should == { "echo" => true }
    end

    # ── Error rescue ────────────────────────────────────────────────────

    it "rescues TaskNotFoundError and sets env error" do
      agent = A2A::Agent.new do
        on "GetTask" do |request|
          raise A2A::TaskNotFoundError.new("task-abc")
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.error"][:code].should == -32001
      env["a2a.error"][:http_status].should == 404
      env["a2a.error"][:message].should == "Task not found"
      env["a2a.error"][:data].first["reason"].should == "TASK_NOT_FOUND"
    end

    it "rescues TaskNotCancelableError and sets env error" do
      agent = A2A::Agent.new do
        on "CancelTask" do |request|
          raise A2A::TaskNotCancelableError.new("task-abc", state: "TASK_STATE_COMPLETED")
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.error"][:code].should == -32002
      env["a2a.error"][:http_status].should == 409
    end

    it "rescues UnsupportedOperationError and sets env error" do
      agent = A2A::Agent.new do
        on "GetExtendedAgentCard" do |request|
          raise A2A::UnsupportedOperationError.new(message: "Not supported")
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.error"][:code].should == -32004
    end

    it "rescues InvalidParamsError and sets env error" do
      agent = A2A::Agent.new do
        on "SendMessage" do |request|
          raise A2A::InvalidParamsError.new("topic is required")
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.error"][:code].should == -32602
      env["a2a.error"][:http_status].should == 422
    end

    it "rescues PushNotificationConfigNotFoundError and sets env error" do
      agent = A2A::Agent.new do
        on "GetTaskPushNotificationConfig" do |request|
          raise A2A::PushNotificationConfigNotFoundError.new("task-abc", "config-123")
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      agent.handlers.first.call(env)

      env["a2a.error"][:code].should == -32001
      env["a2a.error"][:http_status].should == 404
      env["a2a.error"][:data].first["metadata"]["configId"].should == "config-123"
    end

    it "does not rescue non-A2A errors (they propagate)" do
      agent = A2A::Agent.new do
        on "SendMessage" do |request|
          raise RuntimeError, "unexpected bug"
        end
      end

      env = { "a2a.store" => A2A::TaskStore.new, "a2a.request" => {} }
      lambda { agent.handlers.first.call(env) }.should.raise(RuntimeError)
    end
  end
end
