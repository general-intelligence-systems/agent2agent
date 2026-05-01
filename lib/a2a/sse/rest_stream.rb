# frozen_string_literal: true

require_relative "stream"

module A2A
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
    #   stream = A2A::SSE::RestStream.new
    #
    #   Async do
    #     stream.event({ "task" => { ... } })
    #     stream.finish
    #   end
    #
    #   [200, A2A::SSE::Stream.headers, stream]
    #
    class RestStream < Stream
    end
  end
end

test do
  describe "A2A::SSE::RestStream" do
    it "emits bare JSON events (no envelope)" do
      stream = A2A::SSE::RestStream.new

      stream.event({ "statusUpdate" => { "taskId" => "t1" } })
      stream.finish

      chunk = stream.read
      chunk.should.include('"statusUpdate"')
      chunk.should.not.include('"jsonrpc"')
    end

    it "is a subclass of SSE::Stream" do
      stream = A2A::SSE::RestStream.new
      stream.is_a?(A2A::SSE::Stream).should == true
    end
  end
end
