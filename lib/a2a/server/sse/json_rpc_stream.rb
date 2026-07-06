# frozen_string_literal: true

require_relative "stream"

module A2A
  class Server
    module SSE
      # SSE stream that wraps each event in a JSON-RPC 2.0 response envelope.
      #
      # Per the A2A spec, JSON-RPC streaming returns SSE where each `data:` line
      # is a full JSON-RPC response: {"jsonrpc":"2.0","id":N,"result":{...}}
      #
      # Usage:
      #
      #   stream = A2A::Server::SSE::JsonRpcStream.new(
      #     task_id: "t1", context_id: "c1", json_rpc_id: 1
      #   )
      #
      #   Async do
      #     stream.task(status: { state: "TASK_STATE_WORKING", timestamp: "..." })
      #     stream.finish
      #   end
      #
      #   [200, A2A::Server::SSE::Stream.headers, stream]
      #
      class JsonRpcStream < Stream
        def initialize(json_rpc_id:, **options)
          @json_rpc_id = json_rpc_id
          super(**options)
        end

        # Emit an SSE event wrapped in a JSON-RPC envelope.
        #
        # @param data [Hash] the StreamResponse payload (becomes "result")
        #
        def event(data, **opts)
          envelope = {
            "jsonrpc" => "2.0",
            "id"      => @json_rpc_id,
            "result"  => data.respond_to?(:to_h) ? data.to_h : data,
          }
          super(envelope, **opts)
        end
      end
    end
end
end

__END__
  describe "A2A::Server::SSE::JsonRpcStream" do
    it "wraps events in JSON-RPC 2.0 envelopes" do
      stream = A2A::Server::SSE::JsonRpcStream.new(
        task_id: "t1", context_id: "c1", json_rpc_id: 42
      )

      stream.task(status: { state: "TASK_STATE_WORKING", timestamp: "2025-01-01T00:00:00Z" })
      stream.finish

      chunk = stream.read
      chunk.should.include('"jsonrpc"')
      chunk.should.include('"2.0"')
      chunk.should.include('"id":42')  # numeric id preserved
      chunk.should.include('"result"')
    end

    it "is a subclass of SSE::Stream" do
      stream = A2A::Server::SSE::JsonRpcStream.new(
        task_id: "t1", context_id: "c1", json_rpc_id: 1
      )
      stream.is_a?(A2A::Server::SSE::Stream).should == true
      stream.is_a?(::Protocol::HTTP::Body::Readable).should == true
    end

    it "typed methods chain through JSON-RPC envelope" do
      stream = A2A::Server::SSE::JsonRpcStream.new(
        task_id: "t1", context_id: "c1", json_rpc_id: 7
      )

      stream.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: "2025-01-01T00:00:00Z" })
      stream.finish

      chunk = stream.read
      parsed = JSON.parse(chunk.sub(/\Adata: /, "").strip)
      parsed["jsonrpc"].should == "2.0"
      parsed["id"].should == 7
      parsed["result"]["statusUpdate"]["taskId"].should == "t1"
      parsed["result"]["statusUpdate"]["contextId"].should == "c1"
    end
  end
