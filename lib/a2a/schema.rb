# frozen_string_literal: true

require "bundler/setup"
require "a2a"

require "json"
require "json_schemer"
require "uri"

module A2A
  # Schema-validated A2A protocol objects, powered by json_schemer.
  #
  # Loads the bundled data/a2a.json schema, rewrites external $ref
  # values to internal #/definitions/... pointers, and dynamically
  # generates Definition subclasses for each type.
  #
  #   A2A::Schema["Agent Capabilities"]
  #   #=> Class < Definition with .schema, .valid?, reader methods
  #
  #   A2A::Schema["Agent Card"]
  #   #=> Class < Definition
  #
  #   A2A::Schema.list_definitions
  #   #=> ["API Key Security Scheme", "Agent Capabilities", ...]
  #
  module Schema
    DATA_PATH = File.expand_path("../../data/a2a.json", __dir__).freeze

    @definition_classes = {}
    @schemer = nil
    @raw_schema = nil
    @ref_map = nil

    class << self
      # Look up a definition by title.
      #
      #   A2A::Schema["Agent Capabilities"]
      #   #=> Class < Definition
      #
      def [](name)
        @definition_classes[name] ||= begin
          definitions = raw_schema.fetch("definitions", {})

          unless definitions.key?(name)
            raise "No A2A definition found for #{name.inspect}!" \
              "\nAvailable: #{list_definitions.join(", ")}"
          end

          encoded = URI::DEFAULT_PARSER.escape(name)
          ref_schema = schemer.ref("#/definitions/#{encoded}")
          build_definition_class(ref_schema, name, definitions[name])
        end
      end

      # All available definition titles, sorted.
      #
      #   A2A::Schema.list_definitions
      #   #=> ["API Key Security Scheme", "Agent Capabilities", ...]
      #
      def list_definitions
        raw_schema.fetch("definitions", {}).keys.sort
      end

      # The JSONSchemer instance for the full A2A schema bundle.
      # Cached after first access.
      def schemer
        @schemer ||= JSONSchemer.schema(raw_schema)
      end

      # The parsed + ref-rewritten JSON schema hash.
      def raw_schema
        @raw_schema ||= load_and_rewrite_schema
      end

      # Reset all cached state (useful for tests).
      def reset!
        @definition_classes.clear
        @schemer = nil
        @raw_schema = nil
        @ref_map = nil
      end

      private

        # Load data/a2a.json, build the $ref rewrite map, and
        # walk the entire tree replacing external refs with internal ones.
        def load_and_rewrite_schema
          schema = JSON.parse(File.read(DATA_PATH))
          map    = build_ref_map(schema)
          rewrite_refs!(schema, map)
          schema
        end

        # Build a map from external $ref strings to internal
        # #/definitions/Title pointers.
        def build_ref_map(schema)
          return @ref_map if @ref_map

          definitions = schema.fetch("definitions", {})

          pascal_to_title = {}
          definitions.each_key do |title|
            pascal = title.gsub(/\s+/, "")
            pascal_to_title[pascal] = title
          end

          refs = collect_refs(schema)

          map = {}
          refs.each do |ref_str|
            type_name = ref_str
              .sub(/\.jsonschema\.json\z/, "")
              .split(".")
              .last

            if (title = pascal_to_title[type_name])
              encoded = URI::DEFAULT_PARSER.escape(title)
              map[ref_str] = "#/definitions/#{encoded}"
            end
          end

          @ref_map = map
        end

        # Recursively collect all $ref string values from a JSON tree.
        def collect_refs(obj, refs = Set.new)
          case obj
          when Hash
            obj.each do |k, v|
              if k == "$ref" && v.is_a?(String) && !v.start_with?("#")
                refs << v
              else
                collect_refs(v, refs)
              end
            end
          when Array
            obj.each { |v| collect_refs(v, refs) }
          end
          refs
        end

        # Walk the schema tree and replace all external $ref values
        # with their internal #/definitions/... equivalents.
        def rewrite_refs!(obj, map)
          case obj
          when Hash
            obj.each do |k, v|
              if k == "$ref" && v.is_a?(String) && map.key?(v)
                obj[k] = map[v]
              else
                rewrite_refs!(v, map)
              end
            end
          when Array
            obj.each { |v| rewrite_refs!(v, map) }
          end
        end

        # Build a Definition subclass for a specific A2A type.
        def build_definition_class(schema_instance, definition_name, raw_definition)
          properties     = raw_definition.fetch("properties", {})
          camel_keys     = properties.keys
          snake_to_camel = build_snake_to_camel(camel_keys)

          reader_pairs = camel_keys.map { |ck| [camel_to_snake(ck).to_sym, ck] }

          Class.new(Definition) do
            @schema            = schema_instance
            @definition_name   = definition_name
            @schema_properties = camel_keys
            @snake_to_camel    = snake_to_camel

            class << self
              def schema           = @schema
              def definition_name  = @definition_name
              def schema_properties = @schema_properties
              def snake_to_camel_map = @snake_to_camel
            end

            reader_pairs.each do |snake_sym, camel_key|
              define_method(snake_sym) { @data[camel_key] }
            end
          end
        end

        def build_snake_to_camel(camel_keys)
          map = {}
          camel_keys.each do |camel|
            snake = camel_to_snake(camel)
            map[snake] = camel
            map[camel] = camel
          end
          map
        end

        def camel_to_snake(str)
          str.gsub(/([A-Z])/) { "_#{$1.downcase}" }
             .delete_prefix("_")
        end
    end
  end
end

test do
  schema = A2A::Schema

  it "loads the raw schema" do
    schema.raw_schema.should.be.kind_of(Hash)
    schema.raw_schema["definitions"].should.be.kind_of(Hash)
  end

  it "has a schemer instance" do
    schema.schemer.should.be.kind_of(JSONSchemer::Schema)
  end

  it "rewrites $ref values to internal pointers" do
    defs = schema.raw_schema["definitions"]
    external_refs = []
    walk = ->(obj) do
      case obj
      when Hash
        obj.each do |k, v|
          if k == "$ref" && v.is_a?(String) && !v.start_with?("#")
            external_refs << v
          else
            walk.(v)
          end
        end
      when Array
        obj.each { |v| walk.(v) }
      end
    end
    walk.(defs)
    external_refs.should == []
  end

  it "lists all definitions sorted" do
    defs = schema.list_definitions
    defs.should.be.kind_of(Array)
    defs.should.include?("Agent Capabilities")
    defs.should.include?("Agent Card")
    defs.should.include?("Task")
    defs.should.include?("Message")
    defs.should == defs.sort
  end

  it "returns a Class that subclasses Definition" do
    klass = schema["Agent Capabilities"]
    klass.should.be.kind_of(Class)
    (klass < A2A::Schema::Definition).should == true
  end

  it "caches definition classes" do
    a = schema["Agent Capabilities"]
    b = schema["Agent Capabilities"]
    a.object_id.should == b.object_id
  end

  it "raises for unknown definitions" do
    lambda { schema["ThisDoesNotExist999"] }.should.raise(RuntimeError)
  end

  it "has schema_properties listing camelCase keys" do
    klass = schema["Agent Capabilities"]
    klass.schema_properties.should.include?("extendedAgentCard")
    klass.schema_properties.should.include?("streaming")
    klass.schema_properties.should.include?("pushNotifications")
  end

  it "has a definition_name" do
    schema["Agent Capabilities"].definition_name.should == "Agent Capabilities"
  end

  it "creates instances from snake_case keys" do
    caps = schema["Agent Capabilities"].new(
      streaming: true,
      push_notifications: false,
      extended_agent_card: true
    )
    caps.streaming.should == true
    caps.push_notifications.should == false
    caps.extended_agent_card.should == true
  end

  it "creates instances from camelCase keys" do
    caps = schema["Agent Capabilities"].new(
      "streaming" => true,
      "pushNotifications" => false
    )
    caps.streaming.should == true
    caps.push_notifications.should == false
  end

  it "creates instances from symbol camelCase keys" do
    caps = schema["Agent Capabilities"].new(
      streaming: true,
      pushNotifications: false
    )
    caps.streaming.should == true
    caps.push_notifications.should == false
  end

  it "ignores unknown properties" do
    caps = schema["Agent Capabilities"].new(bogus: "ignored", streaming: true)
    caps.streaming.should == true
    caps.to_h.keys.should.not.include?("bogus")
  end

  it "returns camelCase string keys in to_h" do
    caps = schema["Agent Capabilities"].new(streaming: true, push_notifications: false)
    h = caps.to_h
    h.should.be.kind_of(Hash)
    h["streaming"].should == true
    h["pushNotifications"].should == false
  end

  it "validates correct data" do
    caps = schema["Agent Capabilities"].new(streaming: true)
    caps.valid?.should == true
  end

  it "valid! returns true for correct data" do
    caps = schema["Agent Capabilities"].new(streaming: true)
    caps.valid!.should == true
  end

  it "detects type violations" do
    caps = schema["Agent Capabilities"].new(streaming: "not_a_bool")
    caps.valid?.should == false
  end

  it "valid! raises ValidationError for invalid data" do
    caps = schema["Agent Capabilities"].new(streaming: "not_a_bool")
    lambda { caps.valid! }.should.raise(A2A::Schema::ValidationError)
  end

  it "detects additionalProperties violations" do
    caps = schema["Agent Capabilities"].new(streaming: true)
    caps.valid?.should == true
  end

  it "auto-coerces nested Definition instances in constructor" do
    caps = schema["Agent Capabilities"].new(streaming: true)
    card = schema["Agent Card"].new(
      name: "Test Agent",
      version: "1.0.0",
      capabilities: caps
    )
    card.name.should == "Test Agent"
    card.version.should == "1.0.0"
    h = card.to_h
    h["capabilities"].should.be.kind_of(Hash)
    h["capabilities"]["streaming"].should == true
  end

  it "validates Agent Card with nested capabilities" do
    card = schema["Agent Card"].new(
      name: "Test Agent",
      version: "1.0.0",
      capabilities: schema["Agent Capabilities"].new(streaming: true)
    )
    card.valid?.should == true
  end

  it "validates Agent Card with skills array" do
    card = schema["Agent Card"].new(
      name: "Test Agent",
      version: "1.0.0",
      skills: [
        { "id" => "search", "name" => "Web Search", "description" => "Searches the web" }
      ]
    )
    card.valid?.should == true
  end

  it "has a useful inspect" do
    caps = schema["Agent Capabilities"].new(streaming: true)
    caps.inspect.should.include?("Agent Capabilities")
    caps.inspect.should.include?("streaming")
  end

  it "considers two definitions equal when data matches" do
    a = schema["Agent Capabilities"].new(streaming: true)
    b = schema["Agent Capabilities"].new(streaming: true)
    (a == b).should == true
  end

  it "considers two definitions unequal when data differs" do
    a = schema["Agent Capabilities"].new(streaming: true)
    b = schema["Agent Capabilities"].new(streaming: false)
    (a == b).should == false
  end

  it "validates Task with nested TaskStatus" do
    task = schema["Task"].new(
      id: "task-123",
      context_id: "ctx-456",
      status: {
        "state" => "TASK_STATE_SUBMITTED",
        "timestamp" => "2025-01-01T00:00:00Z"
      }
    )
    task.valid?.should == true
    task.id.should == "task-123"
    task.context_id.should == "ctx-456"
  end

  it "validates a Message with parts" do
    msg = schema["Message"].new(
      role: "ROLE_USER",
      message_id: "msg-1",
      parts: [{ "text" => "Hello" }]
    )
    msg.valid?.should == true
    msg.role.should == "ROLE_USER"
    msg.message_id.should == "msg-1"
  end

  it "validates a Part" do
    part = schema["Part"].new(text: "Hello world", media_type: "text/plain")
    part.valid?.should == true
    part.text.should == "Hello world"
    part.media_type.should == "text/plain"
  end

  it "can instantiate every definition without error" do
    schema.list_definitions.each do |name|
      klass = schema[name]
      instance = klass.new
      instance.is_a?(A2A::Schema::Definition).should == true
    end
  end
end
