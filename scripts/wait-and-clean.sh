#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
STACK_NAME="${STACK_NAME:-lightsail-sandbox-pilot}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"
POLL_TIMEOUT="${POLL_TIMEOUT:-1800}"

log() { printf "[%s] %s\n" "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*"; }

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
require aws
require jq

# Pull instance name from outputs
INSTANCE_NAME=$(aws cloudformation describe-stacks   --region "$AWS_REGION"   --stack-name "$STACK_NAME"   --query "Stacks[0].Outputs[?OutputKey=='InstanceNameOut'].OutputValue"   --output text || true)

if [[ -z "${INSTANCE_NAME:-}" || "$INSTANCE_NAME" == "None" ]]; then
  log "ERROR: Could not read InstanceNameOut from stack outputs."
  exit 1
fi

instance_exists() {
  local name="$1"
  set +e
  aws lightsail get-instance --region "$AWS_REGION" --instance-name "$name" >/dev/null 2>&1
  local rc=$?
  set -e
  return $rc
}

log "Waiting for the auto-terminate Lambda to delete the Lightsail instance '$INSTANCE_NAME'..."
start_ts=$(date +%s)

while true; do
  if ! instance_exists "$INSTANCE_NAME"; then
    log "Confirmed: Lightsail instance '$INSTANCE_NAME' no longer exists."
    break
  fi

  now_ts=$(date +%s)
  elapsed=$(( now_ts - start_ts ))
  if (( elapsed > POLL_TIMEOUT )); then
    log "ERROR: Timeout waiting for instance to be deleted (> ${POLL_TIMEOUT}s)."
    exit 2
  fi

  sleep "$POLL_INTERVAL"
done

log "Proceeding to delete CloudFormation stack: $STACK_NAME"
aws cloudformation delete-stack --region "$AWS_REGION" --stack-name "$STACK_NAME"

log "Waiting for stack delete to complete..."
aws cloudformation wait stack-delete-complete --region "$AWS_REGION" --stack-name "$STACK_NAME"

log "SUCCESS: Stack '$STACK_NAME' deleted after Lightsail auto-termination."
