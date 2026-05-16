# frozen_string_literal: true

require "bundler/setup"
require "console"
require "a2a"

module A2A
  class Server
    # Routes incoming A2A operations to registered handler objects.
    #
    # Each handler declares the operations it handles via `#operations`.
    # When an operation arrives, the dispatcher finds all matching handlers
    # and calls them. Errors in one handler do not prevent others from running.
    #
    # The Dispatcher is a Rack app (terminal, not middleware). It reads
    # env["a2a.operation"] set by Triage and fans out to matching handlers.
    #
    class Dispatcher
      def initialize
        @handlers = Hash.new { |h, k| h[k] = [] }
      end

      # Register a handler object.
      #
      # The handler must respond to:
      #   #operations -> Array(String)  (e.g. ["SendMessage", "GetTask"])
      #   #call(env)  -> void           (sets env["a2a.result"])
      #
      def register(handler)
        handler.operations.each do |op|
          @handlers[op] << handler
          Console.info(self) { "Registered #{handler.class.name} for #{op}" }
        end
      end

      def call(env)
        Console.info(self) { "Dispatching: #{env}" }

        operation = env["a2a.operation"]

        if operation
          dispatch(operation, env)
        end

        [200, {}, []]
      end

      def handler_count
        @handlers.values.flatten.size
      end

      private

        def dispatch(operation, env)
          handlers = @handlers[operation]

          if handlers.empty?
            Console.debug(self) { "No handler for operation: #{operation}" }
          else
            handlers.each do |handler|
              begin
                handler.call(env)
              rescue => e
                Console.error(self, "Handler #{handler.class.name} raised #{e.class}", e)
                env["a2a.error"] = { code: -32603, http_status: 500, message: "Internal error" }
              end
            end
          end
        end
    end
  end
end

test do
  describe "A2A::Server::Dispatcher" do
    it "registers and dispatches to handlers" do
      received = []
      handler = Object.new
      handler.define_singleton_method(:operations) { ["SendMessage"] }
      handler.define_singleton_method(:call) { |env| received << env }

      dispatcher = A2A::Server::Dispatcher.new
      dispatcher.register(handler)
      dispatcher.handler_count.should == 1

      env = { "a2a.operation" => "SendMessage" }
      dispatcher.call(env)
      received.length.should == 1
    end

    it "ignores operations with no matching handler" do
      dispatcher = A2A::Server::Dispatcher.new
      env = { "a2a.operation" => "UnknownOp" }
      lambda { dispatcher.call(env) }.should.not.raise
    end

    it "continues dispatching when a handler raises" do
      results = []
      bad_handler = Object.new
      bad_handler.define_singleton_method(:operations) { ["SendMessage"] }
      bad_handler.define_singleton_method(:call) { |_| raise "boom" }

      good_handler = Object.new
      good_handler.define_singleton_method(:operations) { ["SendMessage"] }
      good_handler.define_singleton_method(:call) { |e| results << e }

      dispatcher = A2A::Server::Dispatcher.new
      dispatcher.register(bad_handler)
      dispatcher.register(good_handler)

      env = { "a2a.operation" => "SendMessage" }
      dispatcher.call(env)
      results.length.should == 1
    end

    it "sets internal error on env when a handler raises unexpectedly" do
      bad_handler = Object.new
      bad_handler.define_singleton_method(:operations) { ["SendMessage"] }
      bad_handler.define_singleton_method(:call) { |_| raise "boom" }

      dispatcher = A2A::Server::Dispatcher.new
      dispatcher.register(bad_handler)

      env = { "a2a.operation" => "SendMessage" }
      dispatcher.call(env)
      env["a2a.error"][:code].should == -32603
      env["a2a.error"][:http_status].should == 500
      env["a2a.error"][:message].should == "Internal error"
    end

    it "dispatches to multiple operations from one handler" do
      received = []
      handler = Object.new
      handler.define_singleton_method(:operations) { ["SendMessage", "GetTask"] }
      handler.define_singleton_method(:call) { |env| received << env["a2a.operation"] }

      dispatcher = A2A::Server::Dispatcher.new
      dispatcher.register(handler)

      dispatcher.call({ "a2a.operation" => "SendMessage" })
      dispatcher.call({ "a2a.operation" => "GetTask" })
      received.should == ["SendMessage", "GetTask"]
    end
  end
end
