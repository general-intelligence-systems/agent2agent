# frozen_string_literal true

require "bundler/setup"
require "a2a"

module A2A
  module Bindings
    # Rack app implementing the A2A JSON-RPC 2.0 protocol binding.
    #
    # Dispatches JSON-RPC method names to handler methods derived from
    # Proto.operations. Each operation name (e.g. "SendMessage") maps
    # to a snake_case handler method (e.g. #send_message).
    #
    class JsonRpc
      def initialize(store: TaskStore.new)
        @store = store
      end

      def call(env)
        req = Rack::Request.new(env)
        return error_response(nil, -32600, "Invalid Request") unless req.post?

        begin
          rpc = JSON.parse(req.body.read)
        rescue JSON::ParserError
          return error_response(nil, -32700, "Parse error")
        end

        id     = rpc["id"]
        method = rpc["method"]
        params = rpc["params"] || {}

        op = Proto.operation(method)
        return error_response(id, -32601, "Method not found") unless op

        handler = method_name_for(op.name)
        unless respond_to?(handler, true)
          return error_response(id, -32601, "Method not found")
        end

        begin
          result = send(handler, params)
          success_response(id, result)
        rescue => e
          error_response(id, -32603, e.message)
        end
      end

      private

        def method_name_for(name)
          name.gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, "").to_sym
        end

        def success_response(id, result)
          [200, { "content-type" => "application/json" },
           [JSON.generate(jsonrpc: "2.0", id: id, result: result)]]
        end

        def error_response(id, code, message)
          [200, { "content-type" => "application/json" },
           [JSON.generate(jsonrpc: "2.0", id: id, error: { code: code, message: message })]]
        end
    end
  end
end

test do
  app  = A2A::Bindings::JsonRpc.new
  rack = Rack::MockRequest.new(app)

  A2A::Proto.operations.each do |op|
    it "#{op.json_rpc_method} returns valid #{op.response_type}" do
      body = JSON.generate({
        jsonrpc: "2.0",
        id: 1,
        method: op.json_rpc_method,
        params: {}
      })

      response = rack.post("/", input: body, "CONTENT_TYPE" => "application/json")
      parsed   = JSON.parse(response.body)

      if parsed["error"]
        parsed["error"].should.be.nil
      end

      next unless op.response_schema

      result = parsed["result"]
      schema_obj = op.response_schema.new(result)
      schema_obj.valid?.should == true
    end
  end
end
