# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  # Async-HTTP based A2A protocol client.
  #
  # Discovers agent cards and invokes operations via JSON-RPC:
  #
  #   Async do
  #     client = A2A::Client.new("http://localhost:9292")
  #     card   = client.agent_card
  #     result = client.send_message(message: { ... })
  #     task   = client.get_task(id: "task-123")
  #   end
  #
  class Client
    def initialize(url)
      @url = url.chomp("/")
    end

    # GET /.well-known/agent-card.json
    def agent_card
      get("/.well-known/agent-card.json")
    end

    # JSON-RPC operations — each maps to a Proto operation name.
    Proto.operations.each do |op|
      method_name = op.name.gsub(/([A-Z])/) { "_#{$1.downcase}" }.sub(/^_/, "")

      define_method(method_name) do |params = {}|
        json_rpc(op.name, params)
      end
    end

    private

      def json_rpc(method, params)
        body = JSON.generate(
          jsonrpc: "2.0",
          id: next_id,
          method: method,
          params: params,
        )

        response = post("/", body, "application/json")
        parsed = JSON.parse(response)

        if (error = parsed["error"])
          raise "JSON-RPC error #{error["code"]}: #{error["message"]}"
        end

        parsed["result"]
      end

      def get(path)
        Async do
          internet = Async::HTTP::Internet.new
          response = internet.get("#{@url}#{path}")
          body = response.read
          internet.close
          JSON.parse(body)
        end.wait
      end

      def post(path, body, content_type)
        Async do
          internet = Async::HTTP::Internet.new
          response = internet.post(
            "#{@url}#{path}",
            [["content-type", content_type]],
            [body],
          )
          result = response.read
          internet.close
          result
        end.wait
      end

      def next_id
        @id_counter = (@id_counter || 0) + 1
      end
  end
end
