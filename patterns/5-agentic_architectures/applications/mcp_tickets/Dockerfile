# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Helpdesk tickets MCP server as a container: runs on Amazon ECS (Fargate, ARM64). Standard library only.
FROM --platform=linux/arm64 public.ecr.aws/docker/library/python:3.13-slim

WORKDIR /app

COPY lambda_function.py server.py ./

# POST /mcp (MCP messages) and GET /health (load balancer health check)
EXPOSE 8000
# Write each request's log line straight to Amazon CloudWatch Logs instead of buffering it
ENV PYTHONUNBUFFERED=1
USER 1000

CMD ["python", "server.py"]
