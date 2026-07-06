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
    #   stream = A2A::SSE::RestStream.new(task_id: "t1", context_id: "c1")
    #
    #   Async do
    #     stream.task(status: { state: "TASK_STATE_WORKING", timestamp: "..." })
    #     stream.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: "..." })
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

      attr_reader :task_id, :context_id

      def initialize(task_id:, context_id:, **options)
        @task_id    = task_id
        @context_id = context_id
        super(**options)
      end

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

      # --- Typed event emitters -------------------------------------------
      #
      # Dynamically generated from the StreamResponse schema.
      # Each property in StreamResponse (task, message, statusUpdate,
      # artifactUpdate) gets a snake_case method that:
      #
      #   1. Injects @task_id and @context_id (using the correct key name
      #      for each type — Task uses `id`, others use `task_id`)
      #   2. Builds the schema Definition from kwargs
      #   3. Wraps it in the StreamResponse envelope
      #   4. Calls #event to emit the SSE wire format
      #
      # This means you never pass task_id/context_id manually:
      #
      #   stream.task(status: { state: "TASK_STATE_WORKING" })
      #   stream.artifact_update(artifact: { ... }, append: false, last_chunk: true)
      #   stream.status_update(status: { state: "TASK_STATE_COMPLETED" })
      #   stream.message(role: "ROLE_AGENT", parts: [{ text: "Hello" }])
      #

      stream_response = A2A::Schema["Stream Response"]

      stream_response.property_refs.each do |camel_key, (_kind, title)|
        target_props = A2A::Schema[title].schema_properties

        # Task uses `id` for the task identifier; the other three use `taskId`
        task_id_key = target_props.include?("id") ? :id : :task_id

        # camelCase -> snake_case method name
        method_name = camel_key
          .gsub(/([A-Z])/) { "_#{$1.downcase}" }
          .delete_prefix("_")

        define_method(method_name) do |**kwargs|
          merged = { task_id_key => @task_id, context_id: @context_id }.merge(kwargs)
          event({ camel_key => A2A::Schema[title].new(merged).to_h })
        end
      end
    end
  end
end

__END__
  require "async"

  describe "A2A::SSE::Stream" do
    it "formats SSE events correctly" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")

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
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")

      stream.event("hello", type: "ping")
      stream.finish

      chunk = stream.read
      chunk.should.include("event: ping\n")
      chunk.should.include("data: hello\n")
    end

    it "includes event id when provided" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")

      stream.event("test", id: "42")
      stream.finish

      chunk = stream.read
      chunk.should.include("id: 42\n")
    end

    it "is a Protocol::HTTP::Body::Readable" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")
      stream.is_a?(Protocol::HTTP::Body::Readable).should == true
    end

    it "provides standard SSE headers" do
      headers = A2A::SSE::Stream.headers
      headers["content-type"].should == "text/event-stream"
      headers["cache-control"].should.include("no-cache")
    end

    it "stores task_id and context_id" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")
      stream.task_id.should == "t1"
      stream.context_id.should == "c1"
    end

    # --- Typed emit methods ---

    it "#task emits a task event with injected id and context_id" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")

      stream.task(status: { state: "TASK_STATE_WORKING", timestamp: "2025-01-01T00:00:00Z" })
      stream.finish

      chunk = stream.read
      parsed = JSON.parse(chunk.sub(/\Adata: /, "").strip)
      parsed["task"]["id"].should == "t1"
      parsed["task"]["contextId"].should == "c1"
      parsed["task"]["status"]["state"].should == "TASK_STATE_WORKING"
    end

    it "#status_update emits with injected task_id and context_id" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")

      stream.status_update(status: { state: "TASK_STATE_COMPLETED", timestamp: "2025-01-01T00:00:00Z" })
      stream.finish

      chunk = stream.read
      parsed = JSON.parse(chunk.sub(/\Adata: /, "").strip)
      parsed["statusUpdate"]["taskId"].should == "t1"
      parsed["statusUpdate"]["contextId"].should == "c1"
      parsed["statusUpdate"]["status"]["state"].should == "TASK_STATE_COMPLETED"
    end

    it "#artifact_update emits with injected task_id and context_id" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")

      stream.artifact_update(
        artifact: { artifact_id: "a1", parts: [{ text: "hello" }] },
        append: false,
        last_chunk: true
      )
      stream.finish

      chunk = stream.read
      parsed = JSON.parse(chunk.sub(/\Adata: /, "").strip)
      parsed["artifactUpdate"]["taskId"].should == "t1"
      parsed["artifactUpdate"]["contextId"].should == "c1"
      parsed["artifactUpdate"]["artifact"]["artifactId"].should == "a1"
      parsed["artifactUpdate"]["append"].should == false
      parsed["artifactUpdate"]["lastChunk"].should == true
    end

    it "#message emits with injected task_id and context_id" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")

      stream.message(
        message_id: "m1",
        role: "ROLE_AGENT",
        parts: [{ text: "Hello" }]
      )
      stream.finish

      chunk = stream.read
      parsed = JSON.parse(chunk.sub(/\Adata: /, "").strip)
      parsed["message"]["taskId"].should == "t1"
      parsed["message"]["contextId"].should == "c1"
      parsed["message"]["role"].should == "ROLE_AGENT"
    end

    it "typed methods allow overriding injected values" do
      stream = A2A::SSE::Stream.new(task_id: "t1", context_id: "c1")

      stream.task(id: "override", status: { state: "TASK_STATE_WORKING" })
      stream.finish

      chunk = stream.read
      parsed = JSON.parse(chunk.sub(/\Adata: /, "").strip)
      parsed["task"]["id"].should == "override"
    end
  end
