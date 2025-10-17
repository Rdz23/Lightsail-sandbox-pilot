SHELL := /bin/bash
.ONESHELL:
.PHONY: deploy delete wait clean diagnose delete-force
REGION := ap-southeast-1
STACK_NAME := lightsail-sandbox-pilot
TEMPLATE := templates/lightsail_sandbox_autoterminate.yaml
PARAMS := params.json

deploy:
	 set -euo pipefail
	 echo "[$$(date -u +%Y-%m-%dT%H:%M:%SZ)] Validating CloudFormation template..."
	 aws cloudformation validate-template \
	   --region "$(REGION)" \
	   --template-body file://"$(TEMPLATE)"
	 echo "[$$(date -u +%Y-%m-%dT%H:%M:%SZ)] Deploying stack $(STACK_NAME)..."
	 if aws cloudformation describe-stacks --region "$(REGION)" --stack-name "$(STACK_NAME)" >/dev/null 2>&1; then
	   echo "Stack exists. Updating..."
	   set +e
	   aws cloudformation update-stack \
	     --region "$(REGION)" \
	     --stack-name "$(STACK_NAME)" \
	     --template-body file://"$(TEMPLATE)" \
	     --capabilities CAPABILITY_IAM \
	     --parameters file://"$(PARAMS)" \
	     --tags Key=ENV,Value=Sandbox
	   rc=$$?; set -e
	   if [ $$rc -ne 0 ]; then
	     echo "No updates to apply or update failed (rc=$$rc)."
	   fi
	   echo "Waiting for update to complete..."
	   aws cloudformation wait stack-update-complete \
	     --region "$(REGION)" \
	     --stack-name "$(STACK_NAME)"
	 else
	   echo "Stack not found. Creating..."
	   aws cloudformation create-stack \
	     --region "$(REGION)" \
	     --stack-name "$(STACK_NAME)" \
	     --template-body file://"$(TEMPLATE)" \
	     --capabilities CAPABILITY_IAM \
	     --parameters file://"$(PARAMS)" \
	     --tags Key=ENV,Value=Sandbox
	   echo "Waiting for create to complete..."
	   aws cloudformation wait stack-create-complete \
	     --region "$(REGION)" \
	     --stack-name "$(STACK_NAME)"
	 fi
	 echo "[$$(date -u +%Y-%m-%dT%H:%M:%SZ)] Deployment complete."

delete:
	 set -euo pipefail
	 echo "[$$(date -u +%Y-%m-%dT%H:%M:%SZ)] Disabling termination protection (just in case)..."
	 aws cloudformation update-termination-protection \
	   --region "$(REGION)" \
	   --stack-name "$(STACK_NAME)" \
	   --no-enable-termination-protection || true

	 echo "[$$(date -u +%Y-%m-%dT%H:%M:%SZ)] Deleting stack $(STACK_NAME)..."
	 aws cloudformation delete-stack \
	   --region "$(REGION)" \
	   --stack-name "$(STACK_NAME)"

	 echo "Waiting for delete to complete..."
	 set +e
	 aws cloudformation wait stack-delete-complete \
	   --region "$(REGION)" \
	   --stack-name "$(STACK_NAME)"
	 rc=$$?
	 set -e
	 if [ $$rc -ne 0 ]; then
	   echo "Delete failed (rc=$$rc). Showing failure reasons..."
	   $(MAKE) diagnose
	   exit $$rc
	 fi
	 echo "[$$(date -u +%Y-%m-%dT%H:%M:%SZ)] Stack deleted successfully."

diagnose:
	 set -euo pipefail
	 echo "--- FAILED EVENTS --------------------------------------------------"
	 aws cloudformation describe-stack-events \
	   --region "$(REGION)" \
	   --stack-name "$(STACK_NAME)" \
	   --query 'StackEvents[?contains(ResourceStatus, `FAILED`)]|[].[Timestamp,ResourceType,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
	   --output table || true
	 echo "--- REMAINING RESOURCES --------------------------------------------"
	 aws cloudformation list-stack-resources \
	   --region "$(REGION)" \
	   --stack-name "$(STACK_NAME)" \
	   --query 'StackResourceSummaries[?ResourceStatus!=`DELETE_COMPLETE`].[ResourceType,LogicalResourceId,PhysicalResourceId,ResourceStatus]' \
	   --output table || true

wait:
	 set -euo pipefail
	 echo "[$$(date -u +%Y-%m-%dT%H:%M:%SZ)] Waiting for any stack operation to complete..."
	 aws cloudformation wait stack-exists \
	   --region "$(REGION)" \
	   --stack-name "$(STACK_NAME)"
	 echo "[$$(date -u +%Y-%m-%dT%H:%M:%SZ)] Stack exists and is stable."

clean:
	 set -euo pipefail
	 echo "Cleaning up temporary files..."
	 rm -f *.zip *.log || true
	 echo "Done."

# Optional: a forceful cleanup for the usual blockers (S3 buckets and IAM roles) before retrying delete
delete-force:
	 set -euo pipefail
	 echo "[force] Inspecting stack resources..."
	 aws cloudformation list-stack-resources \
	   --region "$(REGION)" \
	   --stack-name "$(STACK_NAME)" \
	   --output json > .stack_resources.json

	 echo "[force] Emptying S3 buckets found in stack (if any)..."
	 jq -r '.StackResourceSummaries[] | select(.ResourceType=="AWS::S3::Bucket") | .PhysicalResourceId' .stack_resources.json | \
	   while read -r B; do
	     [ -n "$$B" ] || continue
	     echo "  - Emptying s3://$$B"
	     aws s3 rm "s3://$$B" --recursive --region "$(REGION)" || true
	   done

	 echo "[force] Detaching IAM role policies found in stack (if any)..."
	 jq -r '.StackResourceSummaries[] | select(.ResourceType=="AWS::IAM::Role") | .PhysicalResourceId' .stack_resources.json | \
	   while read -r R; do
	     [ -n "$$R" ] || continue
	     echo "  - Cleaning role $$R"
	     for arn in $$(aws iam list-attached-role-policies --role-name "$$R" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
	       aws iam detach-role-policy --role-name "$$R" --policy-arn "$$arn" || true
	     done
	     for pn in $$(aws iam list-role-policies --role-name "$$R" --query 'PolicyNames[]' --output text 2>/dev/null); do
	       aws iam delete-role-policy --role-name "$$R" --policy-name "$$pn" || true
	     done
	     for ip in $$(aws iam list-instance-profiles-for-role --role-name "$$R" --query 'InstanceProfiles[].InstanceProfileName' --output text 2>/dev/null); do
	       aws iam remove-role-from-instance-profile --instance-profile-name "$$ip" --role-name "$$R" || true
	     done
	   done

	 echo "[force] Re-trying delete..."
	 $(MAKE) delete
