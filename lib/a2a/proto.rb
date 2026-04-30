# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  # Parses the A2A protocol's .proto file to extract service operations
  # and bridge them to Schema definition classes for request/response
  # validation.
  #
  # The .proto file is the single normative source for the A2A protocol.
  # This module extracts the service definition (RPC names, request/response
  # types, streaming flags, HTTP bindings) and connects each operation to
  # the corresponding Schema[] class so callers can validate data:
  #
  #   op = A2A::Proto.operation("SendMessage")
  #   op.request_schema.new(params).valid!
  #   op.response_schema.new(result).valid!
  #
  #   A2A::Proto.operations
  #   #=> [Operation("SendMessage", ...), Operation("GetTask", ...), ...]
  #
  module Proto
    PROTO_PATH = File.expand_path("../../data/a2a.proto", __dir__).freeze

    # --- Data classes ---------------------------------------------------

    HttpBinding = Data.define(:verb, :path, :body)

    class Operation
      attr_reader :name, :request_type, :response_type,
                  :server_streaming, :http_bindings

      def initialize(name:, request_type:, response_type:,
                     server_streaming:, http_bindings:)
        @name             = name
        @request_type     = request_type
        @response_type    = response_type
        @server_streaming = server_streaming
        @http_bindings    = http_bindings
      end

      def server_streaming? = @server_streaming

      # Bridge to Schema: convert proto PascalCase type name to
      # the JSON schema title used by A2A::Schema[].
      #
      #   "SendMessageRequest" => Schema["Send Message Request"]
      #
      def request_schema
        A2A::Schema[pascal_to_title(request_type)]
      end

      def response_schema
        return nil if response_type.include?(".")  # google.protobuf.Empty
        A2A::Schema[pascal_to_title(response_type)]
      end

      # JSON-RPC and gRPC method names are identical to the RPC name.
      def json_rpc_method = name
      def grpc_method     = name

      # REST binding from the primary (non-tenant) HTTP annotation.
      def rest_verb = http_bindings.first.verb
      def rest_path = http_bindings.first.path

      def inspect
        "#<Proto::Operation #{name} #{rest_verb.upcase} #{rest_path}>"
      end

      private

        # "SendMessageRequest" => "Send Message Request"
        def pascal_to_title(str)
          str.gsub(/([A-Z])/) { " #{$1}" }.strip
        end
    end

    # --- Module API -----------------------------------------------------

    class << self
      def operations
        @operations ||= parse_operations
      end

      def operation(name)
        operations.find { |op| op.name == name }
      end

      # Reset cached state (for tests).
      def reset!
        @operations = nil
      end

      private

        def parse_operations
          proto_text = File.read(PROTO_PATH)
          service_block = extract_service_block(proto_text)
          parse_rpcs(service_block)
        end

        # Extract the body of `service A2AService { ... }` from the proto text.
        def extract_service_block(text)
          start = text.index(/^service\s+\w+\s*\{/)
          return "" unless start

          depth = 0
          pos = text.index("{", start)
          body_start = pos + 1

          (pos...text.length).each do |i|
            case text[i]
            when "{" then depth += 1
            when "}"
              depth -= 1
              return text[body_start...i] if depth == 0
            end
          end

          ""
        end

        # Parse all `rpc` definitions from the service block text.
        def parse_rpcs(block)
          ops = []

          rpc_chunks = block.split(/(?=^\s*rpc\s)/m).select { |c| c.match?(/^\s*rpc\s/) }

          rpc_chunks.each do |chunk|
            sig = chunk.match(
              /rpc\s+(\w+)\s*\(\s*(\w[\w.]*)\s*\)\s*returns\s*\(\s*(stream\s+)?(\w[\w.]*)\s*\)/
            )
            next unless sig

            name           = sig[1]
            request_type   = sig[2]
            streaming      = !sig[3].nil?
            response_type  = sig[4]

            http_bindings = parse_http_bindings(chunk)

            ops << Operation.new(
              name:             name,
              request_type:     request_type,
              response_type:    response_type,
              server_streaming: streaming,
              http_bindings:    http_bindings,
            )
          end

          ops
        end

        def parse_http_bindings(chunk)
          bindings = []

          http_start = chunk.index("google.api.http")
          return bindings unless http_start

          eq_brace = chunk.index("{", http_start)
          return bindings unless eq_brace

          block_text = extract_braced_block(chunk, eq_brace)
          return bindings unless block_text

          primary = parse_single_binding(block_text)
          bindings << primary if primary

          scan_additional_bindings(block_text).each do |ab_text|
            binding = parse_single_binding(ab_text)
            bindings << binding if binding
          end

          bindings
        end

        def extract_braced_block(text, open_pos)
          depth = 0
          body_start = open_pos + 1

          (open_pos...text.length).each do |i|
            case text[i]
            when "{" then depth += 1
            when "}"
              depth -= 1
              return text[body_start...i] if depth == 0
            end
          end

          nil
        end

        def parse_single_binding(text)
          verb_match = text.match(/\b(get|post|put|patch|delete):\s*"([^"]+)"/)
          return nil unless verb_match

          verb = verb_match[1]
          path = verb_match[2]

          body_match = text.match(/\bbody:\s*"([^"]*)"/)
          body = body_match ? body_match[1] : nil

          HttpBinding.new(verb: verb, path: path, body: body)
        end

        def scan_additional_bindings(text)
          blocks = []
          search_from = 0

          while (ab_pos = text.index("additional_bindings", search_from))
            brace_pos = text.index("{", ab_pos)
            break unless brace_pos

            inner = extract_braced_block(text, brace_pos)
            if inner
              blocks << inner
              search_from = brace_pos + inner.length + 2
            else
              break
            end
          end

          blocks
        end
    end
  end
end

test do
  proto = A2A::Proto

  it "finds 11 operations" do
    proto.operations.size.should == 11
  end

  it "finds all operations by name" do
    expected = %w[
      SendMessage SendStreamingMessage GetTask ListTasks CancelTask
      SubscribeToTask CreateTaskPushNotificationConfig
      GetTaskPushNotificationConfig ListTaskPushNotificationConfigs
      DeleteTaskPushNotificationConfig GetExtendedAgentCard
    ]
    proto.operations.map(&:name).sort.should == expected.sort
  end

  it "looks up an operation by name" do
    proto.operation("SendMessage").should.not.be.nil
    proto.operation("SendMessage").name.should == "SendMessage"
  end

  it "returns nil for unknown operation" do
    proto.operation("NoSuchThing").should.be.nil
  end

  it "SendMessage request type" do
    proto.operation("SendMessage").request_type.should == "SendMessageRequest"
  end

  it "SendMessage response type" do
    proto.operation("SendMessage").response_type.should == "SendMessageResponse"
  end

  it "GetTask returns Task" do
    proto.operation("GetTask").response_type.should == "Task"
  end

  it "CancelTask returns Task" do
    proto.operation("CancelTask").response_type.should == "Task"
  end

  it "GetExtendedAgentCard returns AgentCard" do
    proto.operation("GetExtendedAgentCard").response_type.should == "AgentCard"
  end

  it "DeleteTaskPushNotificationConfig returns google.protobuf.Empty" do
    proto.operation("DeleteTaskPushNotificationConfig")
      .response_type.should == "google.protobuf.Empty"
  end

  it "CreateTaskPushNotificationConfig request and response are both TaskPushNotificationConfig" do
    op = proto.operation("CreateTaskPushNotificationConfig")
    op.request_type.should == "TaskPushNotificationConfig"
    op.response_type.should == "TaskPushNotificationConfig"
  end

  it "SendStreamingMessage is server-streaming" do
    proto.operation("SendStreamingMessage").server_streaming?.should == true
  end

  it "SubscribeToTask is server-streaming" do
    proto.operation("SubscribeToTask").server_streaming?.should == true
  end

  it "SendMessage is not server-streaming" do
    proto.operation("SendMessage").server_streaming?.should == false
  end

  it "GetTask is not server-streaming" do
    proto.operation("GetTask").server_streaming?.should == false
  end

  it "SendMessage has POST /message:send" do
    b = proto.operation("SendMessage").http_bindings.first
    b.verb.should == "post"
    b.path.should == "/message:send"
    b.body.should == "*"
  end

  it "GetTask has GET /tasks/{id=*}" do
    b = proto.operation("GetTask").http_bindings.first
    b.verb.should == "get"
    b.path.should == "/tasks/{id=*}"
    b.body.should.be.nil
  end

  it "ListTasks has GET /tasks" do
    b = proto.operation("ListTasks").http_bindings.first
    b.verb.should == "get"
    b.path.should == "/tasks"
  end

  it "CancelTask has POST /tasks/{id=*}:cancel" do
    b = proto.operation("CancelTask").http_bindings.first
    b.verb.should == "post"
    b.path.should == "/tasks/{id=*}:cancel"
    b.body.should == "*"
  end

  it "DeleteTaskPushNotificationConfig has DELETE verb" do
    b = proto.operation("DeleteTaskPushNotificationConfig").http_bindings.first
    b.verb.should == "delete"
  end

  it "each operation has at least 2 HTTP bindings (primary + tenant)" do
    proto.operations.each do |op|
      op.http_bindings.size.should >= 2
    end
  end

  it "second binding is the tenant-prefixed variant" do
    b = proto.operation("SendMessage").http_bindings[1]
    b.path.should == "/{tenant}/message:send"
    b.verb.should == "post"
  end

  it "GetTask tenant binding" do
    b = proto.operation("GetTask").http_bindings[1]
    b.path.should == "/{tenant}/tasks/{id=*}"
  end

  it "rest_verb returns the primary verb" do
    proto.operation("GetTask").rest_verb.should == "get"
    proto.operation("SendMessage").rest_verb.should == "post"
    proto.operation("DeleteTaskPushNotificationConfig").rest_verb.should == "delete"
  end

  it "rest_path returns the primary path" do
    proto.operation("GetTask").rest_path.should == "/tasks/{id=*}"
    proto.operation("ListTasks").rest_path.should == "/tasks"
  end

  it "json_rpc_method equals the operation name" do
    proto.operations.each do |op|
      op.json_rpc_method.should == op.name
    end
  end

  it "grpc_method equals the operation name" do
    proto.operations.each do |op|
      op.grpc_method.should == op.name
    end
  end

  it "request_schema returns the matching Schema class" do
    op = proto.operation("SendMessage")
    op.request_schema.should == A2A::Schema["Send Message Request"]
  end

  it "response_schema returns the matching Schema class" do
    op = proto.operation("SendMessage")
    op.response_schema.should == A2A::Schema["Send Message Response"]
  end

  it "response_schema for GetTask returns Task schema" do
    op = proto.operation("GetTask")
    op.response_schema.should == A2A::Schema["Task"]
  end

  it "response_schema returns nil for google.protobuf.Empty" do
    op = proto.operation("DeleteTaskPushNotificationConfig")
    op.response_schema.should.be.nil
  end

  it "every operation has a valid request_schema" do
    proto.operations.each do |op|
      op.request_schema.should.be.kind_of(Class)
      (op.request_schema < A2A::Schema::Definition).should == true
    end
  end

  it "every non-Empty operation has a valid response_schema" do
    proto.operations.each do |op|
      next if op.response_type.include?(".")
      op.response_schema.should.be.kind_of(Class)
      (op.response_schema < A2A::Schema::Definition).should == true
    end
  end

  it "can build and validate a SendMessage request" do
    op = proto.operation("SendMessage")
    req = op.request_schema.new(
      message: {
        "messageId" => "msg-1",
        "role" => "ROLE_USER",
        "parts" => [{ "text" => "Hello" }]
      }
    )
    req.valid?.should == true
  end

  it "can build and validate a GetTask request" do
    op = proto.operation("GetTask")
    req = op.request_schema.new(id: "task-123")
    req.valid?.should == true
  end

  it "can build and validate a Task response" do
    op = proto.operation("GetTask")
    resp = op.response_schema.new(
      id: "task-123",
      context_id: "ctx-456",
      status: { "state" => "TASK_STATE_SUBMITTED" }
    )
    resp.valid?.should == true
  end

  it "has a useful inspect" do
    op = proto.operation("SendMessage")
    op.inspect.should.include?("SendMessage")
    op.inspect.should.include?("POST")
    op.inspect.should.include?("/message:send")
  end
end
