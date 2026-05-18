#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.5. Task Listing and Management
# Scenario: Client wants to see all tasks from a specific context or all tasks with a particular status.
#
# Request: All tasks from a specific context
#
# GET /tasks?contextId=c295ea44-7543-4f78-b524-7a38915ad6e4&pageSize=10&historyLength=3 HTTP/1.1
# Host: agent.example.com
# Authorization: Bearer token
#
# Response:
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "tasks": [
#     {
#       "id": "3f36680c-7f37-4a5f-945e-d78981fafd36",
#       "contextId": "c295ea44-7543-4f78-b524-7a38915ad6e4",
#       "status": {
#         "state": "TASK_STATE_COMPLETED",
#         "timestamp": "2024-03-15T10:15:00Z"
#       }
#     }
#   ],
#   "totalSize": 5,
#   "pageSize": 10,
#   "nextPageToken": ""
# }
#
# Request: All working tasks across all contexts
#
# GET /tasks?status=TASK_STATE_WORKING&pageSize=20 HTTP/1.1
# Host: agent.example.com
# Authorization: Bearer token
#
# Response:
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "tasks": [
#     {
#       "id": "789abc-def0-1234-5678-9abcdef01234",
#       "contextId": "another-context-id",
#       "status": {
#         "state": "TASK_STATE_WORKING",
#         "message": {
#           "role": "ROLE_AGENT",
#           "parts": [
#             {
#               "text": "Processing your document analysis..."
#             }
#           ],
#           "messageId": "msg-status-update"
#         },
#         "timestamp": "2024-03-15T10:20:00Z"
#       }
#     }
#   ],
#   "totalSize": 1,
#   "pageSize": 20,
#   "nextPageToken": ""
# }
#
# Pagination Example
#
# GET /tasks?contextId=c295ea44-7543-4f78-b524-7a38915ad6e4&pageSize=10&pageToken=base64-encoded-cursor-token HTTP/1.1
# Host: agent.example.com
# Authorization: Bearer token
#
# Response:
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "tasks": [
#     /* ... additional tasks */
#   ],
#   "totalSize": 15,
#   "pageSize": 10,
#   "nextPageToken": "base64-encoded-next-cursor-token"
# }
#
# Validation Error Example
#
# GET /tasks?pageSize=150&historyLength=-5&status=TASK_STATE_RUNNING HTTP/1.1
# Host: agent.example.com
# Authorization: Bearer token
#
# Response:
#
# HTTP/1.1 400 Bad Request
# Content-Type: application/problem+json
#
# {
#   "status": 400,
#   "detail": "Invalid parameters",
#   "errors": [
#     {
#       "field": "pageSize",
#       "message": "Must be between 1 and 100 inclusive, got 150"
#     },
#     {
#       "field": "historyLength",
#       "message": "Must be non-negative integer, got -5"
#     },
#     {
#       "field": "status",
#       "message": "Invalid status value 'running'. Must be one of: pending, working, completed, failed, canceled"
#     }
#   ]
# }
