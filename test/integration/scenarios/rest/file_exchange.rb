#!/usr/bin/env ruby
# frozen_string_literal: true

# 6.7. File Exchange (Upload and Download)
# Scenario: Client sends an image for analysis, and the agent returns a modified image.
#
# Request with File Upload:
#
# POST /rest/message:send HTTP/1.1
# Host: agent.example.com
# Content-Type: application/a2a+json
# Authorization: Bearer token
#
# {
#   "message": {
#     "role": "ROLE_USER",
#     "parts": [
#       {
#         "text": "Analyze this image and highlight any faces."
#       },
#       {
#         "raw": "iVBORw0KGgoAAAANSUhEUgAAAAUA..."
#         "filename": "input_image.png",
#         "mediaType": "image/png",
#       }
#     ],
#     "messageId": "6dbc13b5-bd57-4c2b-b503-24e381b6c8d6"
#   }
# }
#
# Response with File Reference:
#
# HTTP/1.1 200 OK
# Content-Type: application/a2a+json
#
# {
#   "task": {
#     "id": "43667960-d455-4453-b0cf-1bae4955270d",
#     "contextId": "c295ea44-7543-4f78-b524-7a38915ad6e4",
#     "status": {
#       "state": "TASK_STATE_COMPLETED",
#       "timestamp": "2024-03-15T12:05:00Z"
#     },
#     "artifacts": [
#       {
#         "artifactId": "9b6934dd-37e3-4eb1-8766-962efaab63a1",
#         "name": "processed_image_with_faces.png",
#         "parts": [
#           {
#             "url": "https://storage.example.com/processed/task-bbb/output.png?token=xyz",
#             "filename": "output.png",
#             "mediaType": "image/png"
#           }
#         ]
#       }
#     ]
#   }
# }
