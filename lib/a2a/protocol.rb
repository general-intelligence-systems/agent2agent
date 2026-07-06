# frozen_string_literal: true

require "bundler/setup"

module A2A
  # Namespace for the normative A2A protocol sources.
  #
  # The protocol is defined by two bundled artifacts:
  #
  #   Protobuf   — parses data/a2a.proto (the single normative source) into
  #                service operations with request/response types, streaming
  #                flags, and HTTP bindings.
  #   JsonSchema — loads data/a2a.json and generates schema-validated
  #                Definition classes for each protocol type.
  #
  # Protobuf bridges each operation to its JsonSchema class, so callers can
  # validate protocol payloads end to end:
  #
  #   op = A2A::Protocol::Protobuf.operation("SendMessage")
  #   op.request_schema.new(params).valid!
  #
  #   A2A::Protocol::JsonSchema["Agent Card"].new(card).valid!
  #
  module Protocol
  end
end

require "a2a/protocol/protobuf"
require "a2a/protocol/json_schema"
require "a2a/protocol/json_schema/definition"
require "a2a/protocol/json_schema/validation_error"
