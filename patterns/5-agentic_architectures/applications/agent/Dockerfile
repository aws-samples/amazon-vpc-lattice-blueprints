# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Helpdesk agent: runs on Amazon ECS (Fargate, ARM64) and on Amazon Bedrock AgentCore Runtime (ARM64 only).
FROM --platform=linux/arm64 public.ecr.aws/docker/library/python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py invoke.py ./

# AgentCore Runtime HTTP contract: POST /invocations and GET /ping on port 8080
EXPOSE 8080
USER 1000

CMD ["python", "app.py"]
