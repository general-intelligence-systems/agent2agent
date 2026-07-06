# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Protocol
    module JsonSchema
      # Base class for schema-validated A2A protocol objects.
      #
      # Each A2A definition type (Agent Card, Agent Capabilities, Task, etc.)
      # gets a dynamically-generated subclass of Definition with:
      #   - A JSONSchemer sub-schema attached (.schema)
      #   - Reader methods for each property (snake_case)
      #   - Validation via .valid? / .valid!
      #
      #   caps = A2A::Protocol::JsonSchema["Agent Capabilities"].new(
      #     streaming: true,
      #     push_notifications: false
      #   )
      #   caps.valid?             #=> true
      #   caps.streaming          #=> true
      #   caps.push_notifications #=> false
      #   caps.to_h               #=> { "streaming" => true, "pushNotifications" => false }
      #
      class Definition

        def initialize(hash = {})
          props    = self.class.schema_properties
          snake    = self.class.snake_to_camel_map
          refs     = self.class.property_refs
          @data    = {}

          hash.each do |key, value|
            k = key.to_s

            # Resolve snake_case input to camelCase storage key
            camel = snake[k] || k

            if props.include?(camel)
              @data[camel] = if value.is_a?(Definition)
                value.to_h
              elsif (ref_info = refs[camel])
                wrap_ref(value, ref_info)
              else
                value
              end
            end
          end
        end

        # --- class methods overridden by the factory -----------------------

        def self.schema
          raise "A2A::Protocol::JsonSchema::Definition should NOT be instantiated directly"
        end

        def self.definition_name
          raise "A2A::Protocol::JsonSchema::Definition should NOT be instantiated directly"
        end

        def self.schema_properties
          raise "A2A::Protocol::JsonSchema::Definition should NOT be instantiated directly"
        end

        def self.snake_to_camel_map
          raise "A2A::Protocol::JsonSchema::Definition should NOT be instantiated directly"
        end

        def self.property_refs
          raise "A2A::Protocol::JsonSchema::Definition should NOT be instantiated directly"
        end

        # Reverse of snake_to_camel_map. Built first-entry-wins: the
        # factory inserts the snake_case key before the camelCase
        # identity key, so camelCase storage keys map back to their
        # snake_case reader names.
        def self.camel_to_snake_map
          @camel_to_snake_map ||= snake_to_camel_map.each_with_object({}) do |(key, camel), map|
            map[camel] ||= key
          end
        end

        # --- validation ----------------------------------------------------

        def valid?
          self.class.schema.valid?(to_h)
        end

        def valid!
          errors = self.class.schema.validate(to_h).to_a
          return true if errors.empty?

          raise ValidationError.new(errors,
            definition_name: self.class.definition_name,
            data: to_h
          )
        end

        # --- serialization -------------------------------------------------

        # Returns the data as a plain Hash with camelCase string keys,
        # matching the JSON wire format. Nested Definition instances
        # are auto-coerced via deep_compact.
        def to_h
          deep_compact(@data)
        end

        def ==(other)
          other.is_a?(Definition) && to_h == other.to_h
        end

        # --- pattern matching ------------------------------------------------

        # Supports Ruby hash pattern matching:
        #
        #   case env["a2a.request"].message
        #   in { task_id: String => id, parts: }
        #     ...
        #   end
        #
        # Keys are the snake_case property names, same as the reader
        # methods (camelCase symbols also work). Absent properties are
        # omitted from the result so patterns that require them fail to
        # match. Nested Definition values are returned as-is, so
        # patterns can destructure recursively.
        def deconstruct_keys(keys)
          snake = self.class.snake_to_camel_map

          if keys
            keys.each_with_object({}) do |key, result|
              camel = snake[key.to_s] || key.to_s
              result[key] = @data[camel] if @data.key?(camel)
            end
          else
            camel_to_snake = self.class.camel_to_snake_map
            @data.each_with_object({}) do |(camel, value), result|
              result[(camel_to_snake[camel] || camel).to_sym] = value
            end
          end
        end

        def inspect
          "#<#{self.class.definition_name} #{to_h.inspect}>"
        end

        private

          def wrap_ref(value, ref_info)
            kind, title = ref_info

            case kind
            when :object
              value.is_a?(Hash) ? A2A::Protocol::JsonSchema[title].new(value) : value
            when :array
              if value.is_a?(Array)
                value.map { |el| el.is_a?(Hash) ? A2A::Protocol::JsonSchema[title].new(el) : el }
              else
                value
              end
            when :map
              if value.is_a?(Hash)
                value.transform_values { |v| v.is_a?(Hash) ? A2A::Protocol::JsonSchema[title].new(v) : v }
              else
                value
              end
            else
              value
            end
          end

          def deep_compact(obj)
            case obj
            when Hash
              obj.each_with_object({}) do |(k, v), result|
                compacted = deep_compact(v)
                result[k] = compacted unless compacted.nil?
              end
            when Array
              obj.map { |v| deep_compact(v) }
            when Definition
              obj.to_h
            else
              obj
            end
          end
      end
    end
end
end

__END__
  describe "A2A::Protocol::JsonSchema::Definition#deconstruct_keys" do
    schema = A2A::Protocol::JsonSchema

    it "matches snake_case keys" do
      msg = schema["Message"].new(role: "ROLE_USER", message_id: "m-1", task_id: "t-1")

      case msg
      in { task_id: String => id, role: }
        id.should == "t-1"
        role.should == "ROLE_USER"
      end
    end

    it "matches camelCase keys" do
      msg = schema["Message"].new(role: "ROLE_USER", task_id: "t-1")

      case msg
      in { taskId: String => id }
        id.should == "t-1"
      end
    end

    it "omits absent properties so patterns requiring them fail" do
      msg = schema["Message"].new(role: "ROLE_USER")

      matched = case msg
      in { task_id: String }
        true
      else
        false
      end

      matched.should == false
    end

    it "omits absent properties rather than yielding nil" do
      msg = schema["Message"].new(role: "ROLE_USER")
      msg.deconstruct_keys([:task_id]).key?(:task_id).should == false
    end

    it "destructures nested Definitions recursively" do
      task = schema["Task"].new(
        id:         "t-1",
        context_id: "c-1",
        status:     { "state" => "TASK_STATE_WORKING", "timestamp" => "2025-01-01T00:00:00.000Z" },
      )

      case task
      in { status: { state: } }
        state.should == "TASK_STATE_WORKING"
      end
    end

    it "destructures Definitions inside arrays" do
      msg = schema["Message"].new(
        role:       "ROLE_USER",
        message_id: "m-1",
        parts:      [{ "text" => "hello" }],
      )

      case msg
      in { parts: [{ text: }] }
        text.should == "hello"
      end
    end

    it "returns all properties as snake_case symbols for a nil key filter" do
      msg = schema["Message"].new(role: "ROLE_USER", message_id: "m-1")
      msg.deconstruct_keys(nil).should == { role: "ROLE_USER", message_id: "m-1" }
    end

    it "supports guarded operation-style matching" do
      msg = schema["Message"].new(role: "ROLE_USER", message_id: "m-1", task_id: "")

      matched = case msg
      in { task_id: String => id } if !id.empty?
        :continuation
      else
        :new_task
      end

      matched.should == :new_task
    end
  end
