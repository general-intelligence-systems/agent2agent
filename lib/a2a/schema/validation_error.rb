# frozen_string_literal: true

require "bundler/setup"
require "a2a"

module A2A
  module Schema
    # Raised when a Definition instance fails schema validation.
    #
    # Collects JSONSchemer error details and formats them as a
    # human-readable list with dot-notation field paths.
    #
    #   Agent Card validation failed:
    #     - name is required but missing
    #     - capabilities.streaming must be boolean, got string
    #
    class ValidationError < StandardError
      attr_reader :errors, :definition_name, :data

      def initialize(errors, definition_name:, data: nil)
        @errors          = errors
        @definition_name = definition_name
        @data            = data

        super(build_message)
      end

      private

        def build_message
          lines = errors.map { |e| "  - #{format_error(e)}" }
          "#{definition_name} validation failed:\n#{lines.join("\n")}"
        end

        def format_error(error)
          path  = format_path(error)
          type  = error["type"]

          case type
          when "required"
            missing = error.dig("details", "missing_keys")&.join(", ") || "unknown"
            if path.empty?
              "#{missing} is required but missing"
            else
              "#{path}.#{missing} is required but missing"
            end
          when "type"
            expected = Array(error.dig("schema", "type")).join(" or ")
            "#{path.empty? ? "(root)" : path} must be #{expected}"
          when "enum"
            allowed = error.dig("schema", "enum")&.join(", ") || "?"
            "#{path.empty? ? "(root)" : path} must be one of: #{allowed}"
          when "pattern"
            pattern = error.dig("schema", "pattern")
            "#{path.empty? ? "(root)" : path} must match pattern #{pattern}"
          when "format"
            fmt = error.dig("schema", "format")
            "#{path.empty? ? "(root)" : path} must be a valid #{fmt}"
          when "minimum", "maximum"
            "#{path.empty? ? "(root)" : path} #{error["error"]}"
          when "additionalProperties"
            "#{path.empty? ? "(root)" : path} has unknown properties"
          else
            detail = error["error"] || error["type"] || "invalid"
            "#{path.empty? ? "(root)" : path} #{detail}"
          end
        end

        # Convert JSON pointer like "/properties/capabilities/streaming"
        # to dot notation like "capabilities.streaming"
        def format_path(error)
          pointer = error["data_pointer"].to_s
          return "" if pointer.empty? || pointer == "/"

          pointer.delete_prefix("/").gsub("/", ".")
        end
    end
  end
end

test do
  error_data = [
    {
      "data_pointer" => "",
      "type" => "required",
      "details" => { "missing_keys" => ["name"] },
      "schema" => {},
      "error" => "missing keys: name"
    }
  ]

  err = A2A::Schema::ValidationError.new(error_data, definition_name: "Agent Card")

  it "includes the definition name" do
    err.message.should.include?("Agent Card")
  end

  it "formats required errors" do
    err.message.should.include?("name is required but missing")
  end

  it "stores the errors array" do
    err.errors.should == error_data
  end

  it "stores the definition name" do
    err.definition_name.should == "Agent Card"
  end

  nested = A2A::Schema::ValidationError.new(
    [{ "data_pointer" => "/capabilities/streaming", "type" => "type",
       "schema" => { "type" => "boolean" }, "error" => "wrong type" }],
    definition_name: "Agent Card"
  )

  it "formats nested paths with dot notation" do
    nested.message.should.include?("capabilities.streaming must be boolean")
  end

  additional = A2A::Schema::ValidationError.new(
    [{ "data_pointer" => "/foo", "type" => "additionalProperties",
       "schema" => {}, "error" => "unexpected" }],
    definition_name: "Test"
  )

  it "formats additionalProperties errors" do
    additional.message.should.include?("foo has unknown properties")
  end
end
