# frozen_string_literal: true

require "bundler/setup"
require "a2a"
require "a2a/server/sse"
require "async"

module A2A
  class Server
    module Middleware
      # Sets up an SSE stream builder on `env["a2a.stream"]`.
      #
      # The builder detects the protocol binding (REST vs JSON-RPC) from
      # env and creates the correct stream subclass when `open` is called.
      # The `open` block runs inside an Async fiber and the stream is
      # automatically finished when the block exits (even on exception).
      #
      # If the agent never calls `open`, the builder is removed from env
      # so the binding layer doesn't mistake it for a real stream.
      #
      # Part of the A2A::Server middleware stack, so the agent gets
      # env["a2a.stream"] without declaring anything.
      #
      # Usage:
      #
      #   case env["a2a.operation"]
      #   in "SendStreamingMessage"
      #     env["a2a.stream"].open(task_id: "t1", context_id: "c1") do |s|
      #       s.task(status: { state: "TASK_STATE_WORKING" })
      #       s.status_update(status: { state: "TASK_STATE_COMPLETED" })
      #     end
      #   end
      #
      class SSEStream
        def initialize(app)
          @app = app
        end

        def call(env)
          builder = StreamBuilder.new(env)
          env["a2a.stream"] = builder

          result = @app.call(env)

          # If open was never called, clear the builder so the binding
          # layer doesn't mistake it for a real stream.
          env.delete("a2a.stream") if env["a2a.stream"].equal?(builder)

          result
        end
      end

      # Factory that creates the correct SSE stream subclass based on the
      # protocol binding, then runs the caller's block inside Async with
      # automatic finish on exit.
      #
      # Created by SSEStream middleware — not intended for direct use.
      #
      class StreamBuilder
        def initialize(env)
          @env = env
        end

        # Create and open an SSE stream for the current request.
        #
        # Detects REST vs JSON-RPC from the env, constructs the correct
        # stream subclass, and yields it to the block. The block runs
        # inside an Async fiber. The stream is automatically finished
        # when the block exits, even if an exception is raised.
        #
        # @param task_id    [String] the task identifier for this stream
        # @param context_id [String] the context identifier for this stream
        # @yieldparam stream [A2A::Server::SSE::Stream] the opened stream
        # @return [nil]
        #
        def open(task_id:, context_id:, &block)
          stream = if @env["a2a.json_rpc_id"]
            A2A::Server::SSE::JsonRpcStream.new(
              task_id: task_id, context_id: context_id,
              json_rpc_id: @env["a2a.json_rpc_id"]
            )
          else
            A2A::Server::SSE::RestStream.new(
              task_id: task_id, context_id: context_id
            )
          end

          @env["a2a.stream"] = stream

          Async do
            block.call(stream)
          ensure
            stream.finish
          end

          nil
        end
      end
    end
end
end

__END__
  describe "A2A::Server::Middleware::SSEStream" do
    it "sets a StreamBuilder on env[\"a2a.stream\"]" do
      seen_stream = nil
      downstream = ->(env) { seen_stream = env["a2a.stream"]; :ok }

      mw = A2A::Server::Middleware::SSEStream.new(downstream)
      env = {}
      mw.call(env)

      seen_stream.should.be.kind_of(A2A::Server::Middleware::StreamBuilder)
    end

    it "auto-clears builder if open was never called" do
      downstream = ->(env) { :ok }

      mw = A2A::Server::Middleware::SSEStream.new(downstream)
      env = {}
      mw.call(env)

      env.key?("a2a.stream").should == false
    end

    it "preserves env[\"a2a.stream\"] when open was called" do
      downstream = ->(env) {
        env["a2a.stream"].open(task_id: "t1", context_id: "c1") do |s|
          # no-op
        end
      }

      mw = A2A::Server::Middleware::SSEStream.new(downstream)
      env = {}
      mw.call(env)

      env["a2a.stream"].should.be.kind_of(A2A::Server::SSE::RestStream)
    end

    it "returns the downstream result" do
      downstream = ->(env) { :result_value }

      mw = A2A::Server::Middleware::SSEStream.new(downstream)
      result = mw.call({})

      result.should == :result_value
    end
  end

  describe "A2A::Server::Middleware::StreamBuilder" do
    it "creates a RestStream when no JSON-RPC ID" do
      env = {}
      builder = A2A::Server::Middleware::StreamBuilder.new(env)

      builder.open(task_id: "t1", context_id: "c1") do |s|
        s.should.be.kind_of(A2A::Server::SSE::RestStream)
      end

      env["a2a.stream"].should.be.kind_of(A2A::Server::SSE::RestStream)
    end

    it "creates a JsonRpcStream when JSON-RPC ID is present" do
      env = { "a2a.json_rpc_id" => 42 }
      builder = A2A::Server::Middleware::StreamBuilder.new(env)

      builder.open(task_id: "t1", context_id: "c1") do |s|
        s.should.be.kind_of(A2A::Server::SSE::JsonRpcStream)
      end

      env["a2a.stream"].should.be.kind_of(A2A::Server::SSE::JsonRpcStream)
    end

    it "passes task_id and context_id to the stream" do
      env = {}
      builder = A2A::Server::Middleware::StreamBuilder.new(env)

      builder.open(task_id: "t1", context_id: "c1") do |s|
        s.task_id.should == "t1"
        s.context_id.should == "c1"
      end
    end

    it "auto-finishes the stream when block completes" do
      env = {}
      builder = A2A::Server::Middleware::StreamBuilder.new(env)

      builder.open(task_id: "t1", context_id: "c1") do |s|
        s.task(status: { state: "TASK_STATE_WORKING" })
      end

      stream = env["a2a.stream"]
      # After finish, read drains remaining data then returns nil
      stream.read  # the task event
      stream.read.should.be.nil
    end

    it "auto-finishes even when block raises" do
      env = {}
      builder = A2A::Server::Middleware::StreamBuilder.new(env)

      builder.open(task_id: "t1", context_id: "c1") do |s|
        s.task(status: { state: "TASK_STATE_WORKING" })
        raise "boom"
      end

      stream = env["a2a.stream"]
      stream.read  # the task event
      stream.read.should.be.nil
    end

    it "returns nil" do
      env = {}
      builder = A2A::Server::Middleware::StreamBuilder.new(env)

      result = builder.open(task_id: "t1", context_id: "c1") do |s|
        # no-op
      end

      result.should.be.nil
    end

    it "typed methods inject task_id and context_id" do
      env = {}
      builder = A2A::Server::Middleware::StreamBuilder.new(env)

      builder.open(task_id: "t1", context_id: "c1") do |s|
        s.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: "2025-01-01T00:00:00Z" })
      end

      stream = env["a2a.stream"]
      chunk = stream.read
      parsed = JSON.parse(chunk.sub(/\Adata: /, "").strip)
      parsed["statusUpdate"]["taskId"].should == "t1"
      parsed["statusUpdate"]["contextId"].should == "c1"
    end
  end
