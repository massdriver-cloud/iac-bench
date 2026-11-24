# Mirrors minimal.tfvars so that a bare `tofu plan`/`tofu apply` resolves the
# same smallest-valid instantiation (OpenTofu auto-loads *.auto.tfvars).
# `minimal.tfvars` remains the canonical file to pass with -var-file.
project_id        = "example-project"
region            = "europe-west1"
instance_name     = "pg-example-dev"
network_self_link = "projects/example-project/global/networks/apps-dev"
