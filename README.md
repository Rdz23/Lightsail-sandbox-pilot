# Lightsail-sandbox-pilot

Spin up a **Lightsail sandbox** via CloudFormation. 
The instance auto-terminates (per the template logic), and the stack can be cleaned up automatically afterward.

## Quick start
git clone <YOUR-REPO-URL>.git
cd lightsail-sandbox-pilot

# 1) Configure
cp .env.example .env   # edit if needed

# Optionally edit params.json

# 2) Deploy (create or update)
make deploy

# 3) Wait for auto-terminate & auto-clean the stack
make wait-clean

