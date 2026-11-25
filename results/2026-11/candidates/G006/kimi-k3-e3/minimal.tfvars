# ============================================================================
# Minimal instantiation of the app-storage module.
# An app team copies this, changes five values, and is done.
# ============================================================================

# --- what the app team fills in --------------------------------------------

app_name            = "orders"
environment         = "staging"
resource_group_name = "orders-staging"

# Object (principal) ID of the application's identity in Entra ID — for a
# user-assigned managed identity this is its Principal ID, not its client ID.
# Replace this placeholder with the real one.
identity_principal_id = "11111111-1111-1111-1111-111111111111"

# The blob containers the application needs.
containers = ["uploads", "reports"]

# Pinned here so this example plans without reading the resource group.
# In real use, omit it to inherit the resource group's region.
location = "westeurope"

# Everything else — naming, security, redundancy, soft delete, tags — is the
# module's decision. See README.md "Design decisions".
