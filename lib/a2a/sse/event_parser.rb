# frozen_string_literal: true

require "json"

module A2A
  module SSE
    # Parses raw SSE text chunks into typed StreamResponse schema objects.
    #
    # Faraday's `on_data` callback delivers raw text in arbitrary-sized
    # chunks. This parser buffers them, extracts complete SSE events
    # (delimited by blank lines), parses the JSON from `data:` lines,
    # and yields A2A::Schema["Stream Response"] instances.
    #
    # For the JSON-RPC binding, the parser unwraps the JSON-RPC 2.0
    # envelope (`{"jsonrpc":"2.0","id":N,"result":{...}}`) to extract
    # the StreamResponse payload from `result`.
    #
    # Usage:
    #
    #   parser = A2A::SSE::EventParser.new(binding: :rest)
    #
    #   parser.feed("data: {\"task\":{\"id\":\"t1\"}}\n\n") do |event|
    #     event.task.id  #=> "t1"
    #   end
    #
    class EventParser
      def initialize(binding:)
        @binding = binding
        @buffer  = String.new
      end

      # Feed a raw chunk of SSE text. Yields a StreamResponse for each
      # complete event found in the buffer.
      #
      # @param chunk [String] raw SSE text from the wire
      # @yieldparam event [A2A::Schema::Definition] a Stream Response instance
      #
      def feed(chunk)
        @buffer << chunk

        # SSE events are terminated by a blank line (\n\n).
        # We split on that boundary, keeping any incomplete trailing data
        # in the buffer for the next call.
        while (idx = @buffer.index("\n\n"))
          raw_event = @buffer.slice!(0, idx + 2)
          payload = parse_event(raw_event)
          yield A2A::Schema["Stream Response"].new(payload) if payload
        end
      end

      private

        # Extract JSON from `data:` lines and optionally unwrap JSON-RPC.
        def parse_event(raw)
          data_lines = raw.each_line
            .select { |line| line.start_with?("data:") }
            .map { |line| line.sub(/\Adata:\s?/, "").chomp }

          return nil if data_lines.empty?

          parsed = JSON.parse(data_lines.join("\n"))

          case @binding
          when :json_rpc then parsed["result"]
          else parsed
          end
        rescue JSON::ParserError
          nil
        end
    end
  end
end

test do
  describe "A2A::SSE::EventParser" do
    # --- REST binding ---

    it "parses a single complete SSE event" do
      parser = A2A::SSE::EventParser.new(binding: :rest)
      events = []

      parser.feed("data: {\"task\":{\"id\":\"t1\",\"contextId\":\"c1\"}}\n\n") do |event|
        events << event
      end

      events.size.should == 1
      events[0].should.be.kind_of(A2A::Schema::Definition)
      events[0].task.should.not.be.nil
      events[0].task.id.should == "t1"
    end

    it "parses multiple events in a single chunk" do
      parser = A2A::SSE::EventParser.new(binding: :rest)
      events = []

      chunk = [
        "data: {\"task\":{\"id\":\"t1\",\"contextId\":\"c1\"}}\n\n",
        "data: {\"statusUpdate\":{\"taskId\":\"t1\",\"contextId\":\"c1\",\"status\":{\"state\":\"TASK_STATE_COMPLETED\"}}}\n\n",
      ].join

      parser.feed(chunk) { |e| events << e }

      events.size.should == 2
      events[0].task.should.not.be.nil
      events[1].status_update.should.not.be.nil
    end

    it "handles partial chunks via buffering" do
      parser = A2A::SSE::EventParser.new(binding: :rest)
      events = []

      # First chunk: incomplete event
      parser.feed("data: {\"task\":{\"id\"") { |e| events << e }
      events.size.should == 0

      # Second chunk: completes the event
      parser.feed(":\"t1\",\"contextId\":\"c1\"}}\n\n") { |e| events << e }
      events.size.should == 1
      events[0].task.id.should == "t1"
    end

    it "handles events with event: and id: fields" do
      parser = A2A::SSE::EventParser.new(binding: :rest)
      events = []

      chunk = "event: message\nid: 42\ndata: {\"task\":{\"id\":\"t1\",\"contextId\":\"c1\"}}\n\n"
      parser.feed(chunk) { |e| events << e }

      events.size.should == 1
      events[0].task.id.should == "t1"
    end

    it "skips events with no data lines" do
      parser = A2A::SSE::EventParser.new(binding: :rest)
      events = []

      parser.feed(": comment\n\n") { |e| events << e }
      events.size.should == 0
    end

    it "skips events with invalid JSON" do
      parser = A2A::SSE::EventParser.new(binding: :rest)
      events = []

      parser.feed("data: not-json\n\n") { |e| events << e }
      events.size.should == 0
    end

    # --- JSON-RPC binding ---

    it "unwraps JSON-RPC 2.0 envelope" do
      parser = A2A::SSE::EventParser.new(binding: :json_rpc)
      events = []

      envelope = {
        "jsonrpc" => "2.0",
        "id"      => 1,
        "result"  => {
          "task" => { "id" => "t1", "contextId" => "c1" },
        },
      }

      parser.feed("data: #{JSON.generate(envelope)}\n\n") { |e| events << e }

      events.size.should == 1
      events[0].task.should.not.be.nil
      events[0].task.id.should == "t1"
    end

    it "handles multiple JSON-RPC events" do
      parser = A2A::SSE::EventParser.new(binding: :json_rpc)
      events = []

      [
        { "jsonrpc" => "2.0", "id" => 1, "result" => { "task" => { "id" => "t1", "contextId" => "c1" } } },
        { "jsonrpc" => "2.0", "id" => 1, "result" => { "statusUpdate" => { "taskId" => "t1", "contextId" => "c1", "status" => { "state" => "TASK_STATE_COMPLETED" } } } },
      ].each do |envelope|
        parser.feed("data: #{JSON.generate(envelope)}\n\n") { |e| events << e }
      end

      events.size.should == 2
      events[0].task.should.not.be.nil
      events[1].status_update.should.not.be.nil
    end

    # --- Multi-line data ---

    it "handles multi-line data fields" do
      parser = A2A::SSE::EventParser.new(binding: :rest)
      events = []

      # JSON split across multiple data: lines
      chunk = "data: {\"task\":\n" \
              "data: {\"id\":\"t1\",\"contextId\":\"c1\"}}\n\n"

      parser.feed(chunk) { |e| events << e }

      events.size.should == 1
      events[0].task.id.should == "t1"
    end
  end
end
