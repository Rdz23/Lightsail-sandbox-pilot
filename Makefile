SHELL := /bin/bash

.PHONY: help bootstrap deploy wait-clean cleanup nuke

help:
	@echo "Targets:"
	@echo "  bootstrap   - Check deps & show AWS identity"
	@echo "  deploy      - Create/Update the stack and open ports"
	@echo "  wait-clean  - Wait for Lightsail auto-terminate, then delete stack"
	@echo "  cleanup     - Just delete the stack (no waiting)"
	@echo "  nuke        - Delete stack and any leftover Lightsail instance by name in params.json"

bootstrap:
	@which aws >/dev/null || (echo "Install AWS CLI v2" && exit 1)
	@which jq  >/dev/null || (echo "Install jq" && exit 1)
	@aws sts get-caller-identity

deploy:
	@bash scripts/deploy.sh

wait-clean:
	@bash scripts/wait-and-clean.sh

cleanup:
	@bash scripts/delete-stack.sh

nuke:
	@set -euo pipefail; \
	NAME=$$(jq -r '.[] | select(.ParameterKey=="InstanceName") | .ParameterValue' params.json); \
	echo "[INFO] Deleting stack (if any)..."; \
	bash scripts/delete-stack.sh || true; \
	echo "[INFO] Deleting Lightsail instance (if exists): $$NAME"; \
	aws lightsail delete-instance --instance-name "$$NAME" --output text >/dev/null 2>&1 || true; \
	echo "[INFO] Done."
