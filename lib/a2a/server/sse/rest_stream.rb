# frozen_string_literal: true

require_relative "stream"

module A2A
  class Server
    module SSE
      # SSE stream for the HTTP+JSON/REST binding.
      #
      # Per the A2A spec, REST streaming returns SSE where each `data:` line
      # is a bare StreamResponse JSON object (no envelope wrapping).
      #
      # This is essentially just an alias for Stream — the base class already
      # emits bare JSON. We keep this as a named class for symmetry with
      # JsonRpcStream and to make binding code self-documenting.
      #
      # Usage:
      #
      #   stream = A2A::Server::SSE::RestStream.new(task_id: "t1", context_id: "c1")
      #
      #   Async do
      #     stream.task(status: { state: "TASK_STATE_WORKING", timestamp: "..." })
      #     stream.finish
      #   end
      #
      #   [200, A2A::Server::SSE::Stream.headers, stream]
      #
      class RestStream < Stream
      end
    end
end
end

__END__
  describe "A2A::Server::SSE::RestStream" do
    it "emits bare JSON events (no envelope)" do
      stream = A2A::Server::SSE::RestStream.new(task_id: "t1", context_id: "c1")

      stream.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: "2025-01-01T00:00:00Z" })
      stream.finish

      chunk = stream.read
      chunk.should.include('"statusUpdate"')
      chunk.should.not.include('"jsonrpc"')
    end

    it "is a subclass of SSE::Stream" do
      stream = A2A::Server::SSE::RestStream.new(task_id: "t1", context_id: "c1")
      stream.is_a?(A2A::Server::SSE::Stream).should == true
    end

    it "injects task_id and context_id into typed events" do
      stream = A2A::Server::SSE::RestStream.new(task_id: "t1", context_id: "c1")

      stream.task(status: { state: "TASK_STATE_WORKING" })
      stream.finish

      chunk = stream.read
      parsed = JSON.parse(chunk.sub(/\Adata: /, "").strip)
      parsed["task"]["id"].should == "t1"
      parsed["task"]["contextId"].should == "c1"
    end
  end
