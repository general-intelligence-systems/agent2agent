#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.8. Structured Data Exchange
# Scenario: Client asks for a list of open support tickets in a specific JSON format.
#
# Request:
#
# POST /message:send HTTP/1.1
# Host: agent.example.com
# Content-Type: application/a2a+json
# Authorization: Bearer token
#
# {
#   "message": {
#     "role": "ROLE_USER",
#     "parts": [
#       {
#         "text": "Show me a list of my open IT tickets",
#         "metadata": {
#           "mediaType": "application/json",
#           "schema": {
#             "type": "array",
#             "items": {
#               "type": "object",
#               "properties": {
#                 "ticketNumber": { "type": "string" },
#                 "description": { "type": "string" }
#               }
#             }
#           }
#         }
#       }
#     ],
#     "messageId": "85b26db5-ffbb-4278-a5da-a7b09dea1b47"
#   }
# }
#
# Response with Structured Data:
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "task": {
#     "id": "d8c6243f-5f7a-4f6f-821d-957ce51e856c",
#     "contextId": "c295ea44-7543-4f78-b524-7a38915ad6e4",
#     "status": {
#       "state": "TASK_STATE_COMPLETED",
#       "timestamp": "2025-04-17T17:47:09.680794Z"
#     },
#     "artifacts": [
#       {
#         "artifactId": "c5e0382f-b57f-4da7-87d8-b85171fad17c",
#         "parts": [
#           {
#             "text": "[{\"ticketNumber\":\"REQ12312\",\"description\":\"request for VPN access\"},{\"ticketNumber\":\"REQ23422\",\"description\":\"Add to DL - team-gcp-onboarding\"}]"
#           }
#         ]
#       }
#     ]
#   }
# }
