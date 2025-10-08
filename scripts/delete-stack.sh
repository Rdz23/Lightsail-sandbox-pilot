#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
STACK_NAME="${STACK_NAME:-lightsail-sandbox-pilot}"

log() { printf "[%s] %s\n" "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*"; }

command -v aws >/dev/null 2>&1 || { echo "Missing dependency: aws"; exit 1; }

log "Deleting CloudFormation stack: $STACK_NAME"
aws cloudformation delete-stack --region "$AWS_REGION" --stack-name "$STACK_NAME"

log "Waiting for stack delete to complete..."
aws cloudformation wait stack-delete-complete --region "$AWS_REGION" --stack-name "$STACK_NAME"

log "Done."
