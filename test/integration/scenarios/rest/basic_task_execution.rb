#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.1. Basic Task Execution
# Scenario: Client asks a question and receives a completed task response.
#
# Request:
#
# POST /rest/message:send HTTP/1.1
# Host: agent.example.com
# Content-Type: application/a2a+json
# Authorization: Bearer token
#
# {
#   "message": {
#     "role": "ROLE_USER",
#     "parts": [{"text": "What is the weather today?"}],
#     "messageId": "msg-uuid"
#   }
# }
#
# Response:
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "task": {
#     "id": "task-uuid",
#     "contextId": "context-uuid",
#     "status": {"state": "TASK_STATE_COMPLETED"},
#     "artifacts": [{
#       "artifactId": "artifact-uuid",
#       "name": "Weather Report",
#       "parts": [{"text": "Today will be sunny with a high of 75°F"}]
#     }]
#   }
# }
