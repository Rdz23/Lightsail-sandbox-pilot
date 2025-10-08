#!/usr/bin/env bash
set -euo pipefail

# ===== Load config =====
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
STACK_NAME="${STACK_NAME:-lightsail-sandbox-pilot}"
TEMPLATE="${TEMPLATE:-templates/lightsail_sandbox_autoterminate.yaml}"
PARAMS_FILE="${PARAMS_FILE:-params.json}"

POLL_INTERVAL="${POLL_INTERVAL:-15}"
POLL_TIMEOUT="${POLL_TIMEOUT:-1800}"
OPEN_PORTS="${OPEN_PORTS:-22 80 443}"

log() { printf "[%s] %s\n" "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }
}

instance_exists() {
  local name="$1"
  set +e
  aws lightsail get-instance --region "$AWS_REGION" --instance-name "$name" >/dev/null 2>&1
  local rc=$?
  set -e
  return $rc
}

stack_exists() {
  set +e
  aws cloudformation describe-stacks --region "$AWS_REGION" --stack-name "$STACK_NAME" >/dev/null 2>&1
  local rc=$?
  set -e
  return $rc
}

# ===== Preflight =====
require aws
require jq

[[ -f "$ROOT_DIR/$TEMPLATE" ]] || { echo "Template not found: $TEMPLATE"; exit 1; }
[[ -f "$ROOT_DIR/$PARAMS_FILE" ]] || { echo "Params file not found: $PARAMS_FILE"; exit 1; }

# sanity on params.json
jq -e 'type=="array"' "$ROOT_DIR/$PARAMS_FILE" >/dev/null

# ===== Create or Update Stack =====
if stack_exists; then
  log "Stack exists. Updating: $STACK_NAME"
  set +e
  UPDATE_OUT=$(aws cloudformation update-stack     --region "$AWS_REGION"     --stack-name "$STACK_NAME"     --template-body "file://$ROOT_DIR/$TEMPLATE"     --capabilities CAPABILITY_IAM     --parameters "file://$ROOT_DIR/$PARAMS_FILE" 2>&1)
  RC=$?
  set -e
  if [[ $RC -ne 0 ]]; then
    if echo "$UPDATE_OUT" | grep -q "No updates are to be performed"; then
      log "No changes to update."
    else
      echo "$UPDATE_OUT"
      exit $RC
    fi
  else
    log "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete --region "$AWS_REGION" --stack-name "$STACK_NAME"
    log "Stack updated."
  fi
else
  log "Creating CloudFormation stack: $STACK_NAME"
  aws cloudformation create-stack     --region "$AWS_REGION"     --stack-name "$STACK_NAME"     --template-body "file://$ROOT_DIR/$TEMPLATE"     --capabilities CAPABILITY_IAM     --parameters "file://$ROOT_DIR/$PARAMS_FILE"

  log "Waiting for stack create to complete..."
  aws cloudformation wait stack-create-complete --region "$AWS_REGION" --stack-name "$STACK_NAME"
  log "Stack created."
fi

# ===== Get Outputs =====
INSTANCE_NAME=$(aws cloudformation describe-stacks   --region "$AWS_REGION"   --stack-name "$STACK_NAME"   --query "Stacks[0].Outputs[?OutputKey=='InstanceNameOut'].OutputValue"   --output text || true)

if [[ -z "${INSTANCE_NAME:-}" || "$INSTANCE_NAME" == "None" ]]; then
  log "WARNING: Could not read InstanceNameOut from stack outputs."
  log "If you're using the placeholder template, replace it with your real template."
else
  log "Sandbox instance name: $INSTANCE_NAME"
fi

# ===== Open Ports (22/80/443 by default) =====
if [[ -n "${INSTANCE_NAME:-}" ]] && instance_exists "$INSTANCE_NAME"; then
  for port in $OPEN_PORTS; do
    log "Opening port $port..."
    aws lightsail open-instance-public-ports       --region "$AWS_REGION"       --instance-name "$INSTANCE_NAME"       --port-info "fromPort=$port,toPort=$port,protocol=TCP"
  done
  log "Instance networking configured."
else
  log "No Lightsail instance detected. Skipping port open step."
fi

# ===== Tip =====
log "Tip: To wait for auto-terminate and auto-delete the stack, run:"
log "     scripts/wait-and-clean.sh"
