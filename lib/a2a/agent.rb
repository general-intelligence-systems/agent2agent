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
        Context.new(env).execute(&@block)
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
  end
end
