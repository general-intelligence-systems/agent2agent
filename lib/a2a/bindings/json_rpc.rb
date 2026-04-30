# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Bindings
    # Rack middleware implementing the A2A JSON-RPC 2.0 protocol binding.
    #
    # Strips the JSON-RPC envelope from the inbound request, setting
    # env keys for the method name, request id, and parsed params.
    # Calls downstream. On return, wraps env["a2a.result"] back into
    # a JSON-RPC response envelope.
    #
    # Streaming operations (SendStreamingMessage, SubscribeToTask):
    # When the handler sets env["a2a.stream"] to a Queue or Enumerator,
    # this binding returns a text/event-stream SSE response. Each event
    # is a full JSON-RPC response object wrapped in `data:`.
    #
    class JsonRpc
      def initialize(app)
        @app = app
      end

      def call(env)
        req  = Rack::Request.new(env)
        body = req.body.read
        req.body.rewind

        begin
          rpc = JSON.parse(body)
        rescue JSON::ParserError
          return error_response(nil, -32700, "Parse error")
        end

        unless rpc.is_a?(Hash) && rpc["jsonrpc"] == "2.0"
          return error_response(nil, -32600, "Invalid Request")
        end

        id     = rpc["id"]
        method = rpc["method"]
        params = rpc["params"] || {}

        env["a2a.json_rpc_id"]     = id
        env["a2a.json_rpc_method"] = method
        env["a2a.body"]            = params

        @app.call(env)

        # Check if handler signalled a JSON-RPC error
        if (err = env["a2a.error"])
          return error_response(id, err[:code], err[:message], err[:data])
        end

        # Check if handler set up a streaming response
        if (stream = env["a2a.stream"])
          return streaming_response(id, stream)
        end

        result = env["a2a.result"]
        success_response(id, result)
      end

      private

        def success_response(id, result)
          body = result.respond_to?(:to_h) ? result.to_h : (result || {})
          [200, { "content-type" => "application/json" },
           [JSON.generate(jsonrpc: "2.0", id: id, result: body)]]
        end

        def error_response(id, code, message, data = nil)
          err = { code: code, message: message }
          err[:data] = data if data
          [200, { "content-type" => "application/json" },
           [JSON.generate(jsonrpc: "2.0", id: id, error: err)]]
        end

        def streaming_response(id, stream)
          body = SSEBody.new(id, stream)
          [200, {
            "content-type"  => "text/event-stream",
            "cache-control" => "no-cache",
            "connection"    => "keep-alive",
          }, body]
        end
    end

    # Rack response body that reads from a Queue and emits SSE events.
    # Each event is a JSON-RPC 2.0 response wrapped in `data:`.
    # The stream ends when a nil sentinel is received from the queue.
    class SSEBody
      def initialize(json_rpc_id, stream)
        @json_rpc_id = json_rpc_id
        @stream      = stream
      end

      def each(&block)
        return enum_for(:each) unless block

        loop do
          event = @stream.pop
          break if event.nil? # sentinel = stream done

          result = event.respond_to?(:to_h) ? event.to_h : event
          line = JSON.generate(jsonrpc: "2.0", id: @json_rpc_id, result: result)
          block.call("data: #{line}\n\n")
        end
      end

      def close
        @stream.close if @stream.respond_to?(:close)
      end
    end
  end
end

test do
  server = A2A::Server.new(agent_card: { "name" => "Test" })
  rack   = Rack::MockRequest.new(server)

  A2A::Proto.operations.each do |op|
    it "#{op.json_rpc_method} returns valid #{op.response_type}" do
      body = JSON.generate({
        jsonrpc: "2.0",
        id: 1,
        method: op.json_rpc_method,
        params: {}
      })

      response = rack.post("/a2a", input: body, "CONTENT_TYPE" => "application/json")
      parsed   = JSON.parse(response.body)

      parsed["error"].should.be.nil

      if op.response_schema
        result = parsed["result"]
        schema_obj = op.response_schema.new(result)
        schema_obj.valid?.should == true
      end
    end
  end
end
