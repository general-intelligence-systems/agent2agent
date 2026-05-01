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

require "a2a/proto"
require "a2a/schema"
require "a2a/schema/definition"
require "a2a/schema/validation_error"
require "a2a/task_store"
require "a2a/agent"

require "a2a/server"

require "a2a/client"
