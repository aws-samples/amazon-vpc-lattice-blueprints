# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Self-hosted AI gateway: LiteLLM, pinned by tag and digest (multi-architecture index, the ARM64 image is used).
# Build context: the applications/ directory (docker build -f litellm/Dockerfile applications/), so the gateway
# gets the same OpenAPI spec as the directory API.
FROM --platform=linux/arm64 ghcr.io/berriai/litellm:v1.106.2@sha256:7294b90f868c5c38c99b83021c7ba46f9b439e95f8e32964c925c7d2563a03f7

WORKDIR /app

COPY litellm/config.template.yaml litellm/entrypoint.py ./
COPY api_directory/openapi.json ./openapi.json

EXPOSE 4000

ENTRYPOINT ["python3", "/app/entrypoint.py"]
