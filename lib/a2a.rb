# frozen_string_literal: true

require "bundler/setup"
require "scampi"
require "json"
require "json_schemer"
require "async"
require "async/http/internet"
require "uri"
require "rack"

module A2A
end

require "a2a/errors"
require "a2a/proto"
require "a2a/schema"
require "a2a/schema/definition"
require "a2a/schema/validation_error"
require "a2a/sse"
require "a2a/agent"

require "a2a/server"

require "a2a/faraday/middleware/schema_request"
require "a2a/faraday/middleware/json_rpc/request"
require "a2a/faraday/middleware/json_rpc/response"
require "a2a/faraday/middleware/rest/request"
require "a2a/faraday/middleware/rest/response"
require "a2a/client"
