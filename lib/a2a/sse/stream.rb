# frozen_string_literal: true

require "protocol/http/body/writable"
require "json"

module A2A
  module SSE
    # Async-native SSE body built on Protocol::HTTP::Body::Writable.
    #
    # Falcon's protocol-rack passes Protocol::HTTP::Body::Readable subclasses
    # through untouched — no Enumerable wrapping, no intermediate buffering.
    # This gives us true async streaming with backpressure for free.
    #
    # The gospel (protocol-http) teaches:
    #   - Writable is a producer/consumer queue body
    #   - write() pushes chunks; read() pops them (blocks when empty)
    #   - close_write signals EOF (reader gets nil)
    #   - Client disconnect raises on next write()
    #
    # Usage:
    #
    #   stream = A2A::SSE::Stream.new
    #
    #   Async do
    #     stream.event({ "task" => { ... } })
    #     stream.event({ "statusUpdate" => { ... } })
    #     stream.finish
    #   end
    #
    #   # Return as Rack body — Falcon streams it natively
    #   [200, { "content-type" => "text/event-stream" }, stream]
    #
    class Stream < Protocol::HTTP::Body::Writable
      SSE_HEADERS = {
        "content-type"      => "text/event-stream",
        "cache-control"     => "no-cache, no-transform",
        "x-accel-buffering" => "no",
        "connection"        => "keep-alive",
      }.freeze

      # Emit an SSE event.
      #
      # @param data [Hash, String] the event payload (Hashes are JSON-encoded)
      # @param type [String, nil] optional SSE event type field
      # @param id   [String, nil] optional SSE event id field
      #
      def event(data, type: nil, id: nil)
        payload = data.is_a?(String) ? data : JSON.generate(data)

        buf = String.new
        buf << "event: #{type}\n" if type
        buf << "id: #{id}\n" if id

        # SSE spec: each line of data gets its own `data:` prefix.
        # For single-line JSON this is one line; multi-line is handled correctly.
        payload.each_line do |line|
          buf << "data: #{line.chomp}\n"
        end
        buf << "\n" # blank line terminates the event

        write(buf)
      end

      # Signal end-of-stream.
      # The reader will receive nil on next read(), closing the SSE connection.
      def finish
        close_write
      end

      # Convenience: the SSE headers to return in the Rack response.
      def self.headers
        SSE_HEADERS
      end
    end
  end
end

test do
  require "async"

  describe "A2A::SSE::Stream" do
    it "formats SSE events correctly" do
      stream = A2A::SSE::Stream.new

      stream.event({ "task" => { "id" => "t1" } })
      stream.finish

      chunk = stream.read
      chunk.should.include("data: ")
      chunk.should.include('"task"')
      chunk.should.end_with("\n\n")

      # After finish, read returns nil
      stream.read.should.be.nil
    end

    it "includes event type when provided" do
      stream = A2A::SSE::Stream.new

      stream.event("hello", type: "ping")
      stream.finish

      chunk = stream.read
      chunk.should.include("event: ping\n")
      chunk.should.include("data: hello\n")
    end

    it "includes event id when provided" do
      stream = A2A::SSE::Stream.new

      stream.event("test", id: "42")
      stream.finish

      chunk = stream.read
      chunk.should.include("id: 42\n")
    end

    it "is a Protocol::HTTP::Body::Readable" do
      stream = A2A::SSE::Stream.new
      stream.is_a?(Protocol::HTTP::Body::Readable).should == true
    end

    it "provides standard SSE headers" do
      headers = A2A::SSE::Stream.headers
      headers["content-type"].should == "text/event-stream"
      headers["cache-control"].should.include("no-cache")
    end
  end
end
