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
