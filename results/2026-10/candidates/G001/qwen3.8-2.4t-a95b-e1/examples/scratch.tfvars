# A throwaway bucket for a scratch/experiment environment: no versioning,
# destroyable even when non-empty, and no IAM policy to tidy up.

application        = "demoapp"
environment        = "sandbox"
versioning_enabled = false
force_destroy      = true
create_app_policy  = false
