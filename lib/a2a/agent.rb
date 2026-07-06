# frozen_string_literal: true

require "bundler/setup"
require "console"
require "a2a"

module A2A
  # Builds a complete A2A server (a rack app) from a handler block —
  # the one-call entrypoint.
  #
  # The block receives the rack env and returns a domain object
  # (A2A::Protocol::JsonSchema::Definition) — the binding layer formats
  # it into HTTP. Route operations with pattern matching:
  #
  #   run A2A.agent(agent_card: { "name" => "My Agent" }) do |env|
  #     case env["a2a.operation"]
  #     in "SendMessage"
  #       A2A::Protocol::JsonSchema["Send Message Response"].new({})
  #     in "GetTask"
  #       task = Task.find_by(id: env["a2a.request"].id)
  #       raise A2A::TaskNotFoundError.new(env["a2a.request"].id) unless task
  #       task.to_a2a
  #     end
  #   end
  #
  # To route on request contents as well, match a tuple — Definition
  # implements deconstruct_keys, so patterns destructure recursively:
  #
  #   case [env["a2a.operation"], env["a2a.request"]]
  #   in ["SendMessage", { message: { task_id: String => id } }] if !id.empty?
  #     # continuation of task `id`
  #   in ["SendMessage", _]
  #     # new task
  #   end
  #
  def self.agent(**options, &block) = Server.new(**options, &block)

  # Wraps the agent block with the server's error boundary:
  #
  #   NoMatchingPatternError -> A2A::UnsupportedOperationError, so an
  #     unhandled operation falls out of `case ... in` with no else branch
  #   A2A::Error             -> returned for the binding layer to format
  #   anything else          -> logged, returned as a JSON-RPC internal error
  #
  class Agent
    def initialize(&block)
      raise ArgumentError, "agent requires a block" unless block

      @block = block
    end

    def call(env)
      @block.call(env)
    rescue NoMatchingPatternError
      A2A::UnsupportedOperationError.new(
        message: "Operation not supported: #{env["a2a.operation"]}"
      )
    rescue A2A::Error => e
      e
    rescue => e
      Console.error(self, "Agent raised #{e.class}: #{e.message}", e)
      A2A::Error.new("Internal error", code: -32603, http_status: 500)
    end
  end
end

__END__
  describe "A2A.agent" do
    it "returns an A2A::Server" do
      server = A2A.agent(agent_card: { "name" => "Test" }) { |env| nil }
      server.should.be.is_a(A2A::Server)
    end
  end

  describe "A2A::Agent" do
    it "requires a block" do
      lambda { A2A::Agent.new }.should.raise(ArgumentError)
    end

    it "calls the block with env and returns its result" do
      agent = A2A::Agent.new { |env| env["a2a.operation"] }
      agent.call({ "a2a.operation" => "SendMessage" }).should == "SendMessage"
    end

    it "routes operations with pattern matching" do
      agent = A2A::Agent.new do |env|
        case env["a2a.operation"]
        in "SendMessage" then :sent
        in "GetTask" then :got
        end
      end

      agent.call({ "a2a.operation" => "SendMessage" }).should == :sent
      agent.call({ "a2a.operation" => "GetTask" }).should == :got
    end

    it "returns UnsupportedOperationError when no pattern matches" do
      agent = A2A::Agent.new do |env|
        case env["a2a.operation"]
        in "SendMessage" then :sent
        end
      end

      result = agent.call({ "a2a.operation" => "UnknownOp" })
      result.should.be.is_a(A2A::UnsupportedOperationError)
      result.code.should == -32004
    end

    it "returns A2A::Error when the block raises one" do
      agent = A2A::Agent.new { |env| raise A2A::TaskNotFoundError.new("t-1") }

      result = agent.call({})
      result.should.be.is_a(A2A::TaskNotFoundError)
      result.code.should == -32001
    end

    it "returns internal error when the block raises unexpectedly" do
      agent = A2A::Agent.new { |env| raise "boom" }

      result = agent.call({})
      result.should.be.is_a(A2A::Error)
      result.code.should == -32603
      result.http_status.should == 500
    end

    it "matches request contents via deconstruct_keys" do
      agent = A2A::Agent.new do |env|
        case [env["a2a.operation"], env["a2a.request"]]
        in ["SendMessage", { message: { task_id: String => id } }] if !id.empty?
          [:continuation, id]
        in ["SendMessage", _]
          :new_task
        end
      end

      request = A2A::Protocol::JsonSchema["Send Message Request"].new(
        message: { "taskId" => "t-1", "role" => "ROLE_USER" }
      )
      agent.call({ "a2a.operation" => "SendMessage", "a2a.request" => request })
        .should == [:continuation, "t-1"]

      request = A2A::Protocol::JsonSchema["Send Message Request"].new(
        message: { "role" => "ROLE_USER" }
      )
      agent.call({ "a2a.operation" => "SendMessage", "a2a.request" => request })
        .should == :new_task
    end
  end
