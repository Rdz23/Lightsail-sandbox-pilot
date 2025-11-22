# Context
For software development team experimentation environment safe, low-cost environment to experiment, test ideas, and validate new technologies without impacting production or incurring unpredictable costs. A Sandbox Environment is an isolated, pre-configured AWS space where developers can quickly spin up resources, try out tools, and learn new cloud technologies.

**By leveraging AWS Lightsail, we gain:**

  Simplicity – easy setup with predictable pricing.
  Governance – predefined instance types, Linux-only with tagged "Sandbox"
  Enablement – developers can “jump in” immediately, with Docker, Node.js, Python, and AWS CLI already installed, and other if needed.
  Auto-stop at night (via Lambda/EventBridge) to minimize unnecessary runtime.

# Lightsail Sandbox Pilot

Spin up a **guard-railed Lightsail sandbox** via CloudFormation. The instance auto-terminates (per your template logic), and the stack can be cleaned up automatically afterward.

> 🚧 **Important:** This repo includes a placeholder CloudFormation template at `templates/lightsail_sandbox_autoterminate.yaml`.
> Replace its contents with your actual template that creates the Lightsail instance and auto-termination Lambda.

## Quick start

```bash
git clone <YOUR-REPO-URL>.git Lightsail-sandbox-pilot
cd Lightsail-sandbox-pilot

# 1) Configure
cp .env.example .env   # edit if needed
# Optionally edit params.json

# 2) Deploy (create or update)
make deploy

# 3) Wait for auto-terminate & auto-clean the stack
make wait-clean
```

## Prereqs
- AWS CLI v2 with credentials (IAM permissions for CloudFormation, Lightsail, SNS)
- `jq` installed

## Configuration
- `.env` controls region, stack/template paths, ports, and polling.
- `params.json` passes CloudFormation parameters:
  - `InstanceName` – Lightsail instance name (e.g., `Sandbox-env`)
  - `BundleId` – allowed Lightsail bundle (`nano_3_0`, `micro_3_0`, etc.)
  - `SnsTopicArn` – SNS topic for notifications

## Common Tasks

- **Update config and redeploy**
  ```bash
  make deploy
  ```

- **Wait for auto-terminate and delete stack**
  ```bash
  make wait-clean
  ```

- **Force delete stack only**
  ```bash
  make cleanup
  ```

- **Nuke (stack + instance by name from params.json)**
  ```bash
  make nuke
  ```

## Notes
- Ports `22 80 443` are opened automatically after stack completion (override via `OPEN_PORTS` in `.env`).
- Scripts are **idempotent** where possible:
  - `deploy.sh` will **update** the stack if it already exists, otherwise **create** it.
- If you use the placeholder template, the deploy step will **skip** opening ports (no instance detected).
