#!/bin/bash
#
# This script sends a test prompt to the VLLM inference server.
#
# Pre-requisite: You must have a port-forward running in another terminal:
#   kubectl port-forward service/vllm-gemma-3-27b-a100-service 8080:80
#
# Model: update the model to the model you are querying against.

curl http://localhost:8080/v1/completions \
-H "Content-Type: application/json" \
-d '{
    "model": "gemma-3-27b-it",
    "prompt": "Why is the sky blue?",
    "max_tokens": 1000
}'
