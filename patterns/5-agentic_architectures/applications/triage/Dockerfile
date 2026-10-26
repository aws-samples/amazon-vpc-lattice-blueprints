# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Helpdesk triage agent (A2A server): runs on Amazon ECS (Fargate, ARM64) and on Amazon Bedrock AgentCore Runtime.
FROM --platform=linux/arm64 public.ecr.aws/docker/library/python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# A2A contract (AgentCore Runtime A2A protocol): port 9000, root path
EXPOSE 9000
USER 1000

CMD ["python", "app.py"]
