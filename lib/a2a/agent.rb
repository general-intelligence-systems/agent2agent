# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  # DSL wrapper that collects operation handlers for an A2A agent.
  #
  # An Agent produces handler objects that conform to the Dispatcher's
  # contract (#operations, #call). Register an agent on a Server the
  # same way you would register a plain handler.
  #
  #   agent = A2A::Agent.new do
  #     on "SendMessage" do
  #       respond_with -> (env) {
  #         A2A::Protocol::JsonSchema["Send Message Response"].new({})
  #       }
  #     end
  #
  #     on "GetTask" do
  #       respond_with -> (env) {
  #         task = Task.find_by(id: env["a2a.request"].id)
  #         raise A2A::TaskNotFoundError.new(env["a2a.request"].id) unless task
  #         task.to_a2a
  #       }
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

    # Define a handler stack for one or more A2A operations.
    #
    # The block is evaluated at definition time to build the middleware
    # stack. Use `use` to add middleware, `respond_with` to set the
    # terminal handler.
    #
    #   on "SendMessage" do
    #     use SomeMiddleware
    #     respond_with -> (env) { ... }
    #   end
    #
    def on(*operations, &block)
      raise ArgumentError, "on requires at least one operation" if operations.empty?
      raise ArgumentError, "on requires a block" unless block

      builder = StackBuilder.new
      builder.instance_eval(&block)

      handler = Handler.new(
        operations: operations.flatten,
        app:        builder.to_app
      )

      @handlers << handler
      handler
    end

    # Builds a per-operation middleware stack.
    # Collects `use` and `respond_with` calls, compiles into a callable app.
    class StackBuilder
      def initialize
        @middleware = []
        @terminal   = nil
      end

      def use(middleware, *args, &block)
        @middleware << [middleware, args, block]
      end

      def respond_with(callable)
        @terminal = callable
      end

      def to_app
        raise ArgumentError, "respond_with is required" unless @terminal

        app = Terminal.new(@terminal)

        @middleware.reverse_each do |klass, args, block|
          app = klass.new(app, *args, &block)
        end

        app
      end
    end

    # Wraps the respond_with lambda as a callable.
    # Returns whatever the lambda returns.
    class Terminal
      def initialize(callable)
        @callable = callable
      end

      def call(env)
        @callable.call(env)
      end
    end

    # Handler object produced by the #on DSL method.
    # Conforms to the Dispatcher contract: #operations, #call.
    class Handler
      attr_reader :operations

      def initialize(operations:, app:)
        @operations = operations
        @app        = app
      end

      def call(env)
        @app.call(env)
      end
    end
  end
end

__END__
  describe "A2A::Agent" do
    it "registers handlers via the on DSL" do
      agent = A2A::Agent.new do
        on "SendMessage" do
          respond_with -> (env) { :ok }
        end
      end

      agent.handlers.length.should == 1
      agent.handlers.first.operations.should == ["SendMessage"]
    end

    it "registers multiple operations on a single handler" do
      agent = A2A::Agent.new do
        on "SendMessage", "GetTask" do
          respond_with -> (env) { :ok }
        end
      end

      agent.handlers.first.operations.should == ["SendMessage", "GetTask"]
    end

    it "raises if on is called without operations" do
      lambda {
        A2A::Agent.new do
          on do
            respond_with -> (env) { :ok }
          end
        end
      }.should.raise(ArgumentError)
    end

    it "raises if on is called without a block" do
      lambda {
        agent = A2A::Agent.new
        agent.on "SendMessage"
      }.should.raise(ArgumentError)
    end

    it "raises if respond_with is not provided" do
      lambda {
        A2A::Agent.new do
          on "SendMessage" do
            use Class.new
          end
        end
      }.should.raise(ArgumentError)
    end

    it "returns the respond_with lambda result" do
      agent = A2A::Agent.new do
        on "SendMessage" do
          respond_with -> (env) { { "echo" => true } }
        end
      end

      env = { "a2a.request" => {} }
      result = agent.handlers.first.call(env)
      result.should == { "echo" => true }
    end

    it "returns a Schema::Definition from respond_with" do
      schema_obj = A2A::Protocol::JsonSchema["Task"].new(
        "id"        => "t-1",
        "contextId" => "c-1",
        "status"    => { "state" => "TASK_STATE_COMPLETED", "timestamp" => "2025-01-01T00:00:00.000Z" },
      )

      agent = A2A::Agent.new do
        on "GetTask" do
          respond_with -> (env) { schema_obj }
        end
      end

      env = { "a2a.request" => {} }
      result = agent.handlers.first.call(env)
      result.should == schema_obj
    end

    it "passes env to the respond_with lambda" do
      seen_env = nil

      agent = A2A::Agent.new do
        on "SendMessage" do
          respond_with -> (env) { seen_env = env; :ok }
        end
      end

      env = { "a2a.request" => { "msg" => "hi" } }
      agent.handlers.first.call(env)
      seen_env.should == env
    end

    it "executes middleware in order" do
      order = []

      mw1 = Class.new do
        define_method(:initialize) { |app| @app = app }
        define_method(:call) { |env| order << :mw1; @app.call(env) }
      end

      mw2 = Class.new do
        define_method(:initialize) { |app| @app = app }
        define_method(:call) { |env| order << :mw2; @app.call(env) }
      end

      agent = A2A::Agent.new do
        on "SendMessage" do
          use mw1
          use mw2
          respond_with -> (env) { order << :terminal; :done }
        end
      end

      env = { "a2a.request" => {} }
      agent.handlers.first.call(env)
      order.should == [:mw1, :mw2, :terminal]
    end

    it "middleware can intercept and return early" do
      blocker = Class.new do
        define_method(:initialize) { |app| @app = app }
        define_method(:call) { |env| :blocked }
      end

      agent = A2A::Agent.new do
        on "SendMessage" do
          use blocker
          respond_with -> (env) { :should_not_reach }
        end
      end

      env = { "a2a.request" => {} }
      result = agent.handlers.first.call(env)
      result.should == :blocked
    end

    # ── Error behavior ─────────────────────────────────────────────────
    # Errors propagate to the Dispatcher which catches them.

    it "lets A2A::Error propagate (Dispatcher catches it)" do
      agent = A2A::Agent.new do
        on "GetTask" do
          respond_with -> (env) {
            raise A2A::TaskNotFoundError.new("task-abc")
          }
        end
      end

      env = { "a2a.request" => {} }
      lambda { agent.handlers.first.call(env) }.should.raise(A2A::TaskNotFoundError)
    end

    it "lets unexpected errors propagate" do
      agent = A2A::Agent.new do
        on "SendMessage" do
          respond_with -> (env) {
            raise RuntimeError, "unexpected bug"
          }
        end
      end

      env = { "a2a.request" => {} }
      lambda { agent.handlers.first.call(env) }.should.raise(RuntimeError)
    end
  end
