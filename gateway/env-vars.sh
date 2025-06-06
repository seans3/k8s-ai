#!/bin/bash
##################################################
#
# Name: env-vars.sh
# Description:
#   Set environment variables used in the
#   creation of ai inference servers on
#   Kubernetes within Google Cloud Platform.
#
# Example: $ source env-vars.sh
#
##################################################

set +x

export PROJECT_ID=<PROJECT_ID>
echo "PROJECT_ID=${PROJECT_ID}"

export REGION=us-central1
echo "REGION=${REGION}"

export CLUSTER_NAME=ai-inf-gateway
echo "CLUSTER_NAME=${CLUSTER_NAME}"

export CHANNEL="rapid"
echo "CHANNEL=${CHANNEL}"

export NAMESPACE=ai-test
echo "NAMESPACE=${NAMESPACE}"

export HF_TOKEN=<HUGGING_FACE_TOKEN>
