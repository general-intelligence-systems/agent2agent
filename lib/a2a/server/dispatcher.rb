# frozen_string_literal: true

require "bundler/setup"
require "console"
require "a2a"

module A2A
  class Server
    # Routes incoming A2A operations to their registered handler stacks.
    #
    # Each operation maps to exactly one Rack app (a compiled middleware
    # stack built by the Agent DSL). The Dispatcher is a terminal Rack app
    # that reads env["a2a.operation"] set by Triage, looks up the matching
    # route, and calls it.
    #
    # Returns domain objects (A2A::Protocol::JsonSchema::Definition or A2A::Error) —
    # the binding layer is responsible for formatting these into HTTP.
    #
    class Dispatcher
      def initialize
        @routes = {}
      end

      # Register a handler object.
      #
      # The handler must respond to:
      #   #operations -> Array(String)  (e.g. ["SendMessage", "GetTask"])
      #   #call(env)  -> A2A::Protocol::JsonSchema::Definition | A2A::Error
      #
      def register(handler)
        handler.operations.each do |op|
          @routes[op] = handler
          Console.info(self) { "Registered #{handler.class.name} for #{op}" }
        end
      end

      def call(env)
        operation = env["a2a.operation"]
        app = @routes[operation]

        unless app
          raise A2A::UnsupportedOperationError.new(
            message: "Operation not supported: #{operation}"
          )
        end

        app.call(env)
      rescue A2A::Error => e
        e
      rescue => e
        Console.error(self, "Handler raised #{e.class}: #{e.message}", e)
        A2A::Error.new("Internal error", code: -32603, http_status: 500)
      end

      def handler_count
        @routes.size
      end
    end
  end
end

__END__
  describe "A2A::Server::Dispatcher" do
    it "registers and dispatches to a handler" do
      handler = Object.new
      handler.define_singleton_method(:operations) { ["SendMessage"] }
      handler.define_singleton_method(:call) { |env| :dispatched }

      dispatcher = A2A::Server::Dispatcher.new
      dispatcher.register(handler)
      dispatcher.handler_count.should == 1

      env = { "a2a.operation" => "SendMessage" }
      result = dispatcher.call(env)
      result.should == :dispatched
    end

    it "returns UnsupportedOperationError for unknown operations" do
      dispatcher = A2A::Server::Dispatcher.new
      env = { "a2a.operation" => "UnknownOp" }
      result = dispatcher.call(env)
      result.should.be.is_a(A2A::UnsupportedOperationError)
      result.code.should == -32004
    end

    it "returns A2A::Error when handler raises one" do
      handler = Object.new
      handler.define_singleton_method(:operations) { ["SendMessage"] }
      handler.define_singleton_method(:call) { |_| raise A2A::TaskNotFoundError.new("t-1") }

      dispatcher = A2A::Server::Dispatcher.new
      dispatcher.register(handler)

      result = dispatcher.call({ "a2a.operation" => "SendMessage" })
      result.should.be.is_a(A2A::TaskNotFoundError)
      result.code.should == -32001
    end

    it "returns internal error when handler raises unexpected exception" do
      handler = Object.new
      handler.define_singleton_method(:operations) { ["SendMessage"] }
      handler.define_singleton_method(:call) { |_| raise "boom" }

      dispatcher = A2A::Server::Dispatcher.new
      dispatcher.register(handler)

      result = dispatcher.call({ "a2a.operation" => "SendMessage" })
      result.should.be.is_a(A2A::Error)
      result.code.should == -32603
      result.http_status.should == 500
    end

    it "dispatches to multiple operations from one handler" do
      received = []
      handler = Object.new
      handler.define_singleton_method(:operations) { ["SendMessage", "GetTask"] }
      handler.define_singleton_method(:call) { |env| received << env["a2a.operation"]; :ok }

      dispatcher = A2A::Server::Dispatcher.new
      dispatcher.register(handler)

      dispatcher.call({ "a2a.operation" => "SendMessage" })
      dispatcher.call({ "a2a.operation" => "GetTask" })
      received.should == ["SendMessage", "GetTask"]
    end
  end
