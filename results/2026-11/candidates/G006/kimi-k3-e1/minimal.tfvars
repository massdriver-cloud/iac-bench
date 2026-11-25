# The smallest valid instantiation of the module.
# Copy this file, change the values, then:
#   tofu init
#   tofu plan -var-file=minimal.tfvars
#   tofu apply -var-file=minimal.tfvars

app_name            = "orders"
environment         = "staging"
resource_group_name = "orders-staging"
location            = "westeurope"

# Object ID of the application's Entra identity (managed identity or service
# principal). Not the app/client ID — the object ID of the identity.
app_identity_principal_id = "11111111-1111-1111-1111-111111111111"

# Blob containers the application needs. All private.
containers = ["uploads", "media", "reports"]
