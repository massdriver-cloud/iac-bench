# Smallest valid instantiation of the standard application storage module.
# Copy this, adjust the values, done — everything else is the module's job.

# Globally unique, 3-24 lowercase letters/digits.
name = "stordersstgxa7k2"

# The application's existing resource group; storage lives next to the app.
resource_group_name = "orders-staging"

# Explicit region keeps this example self-contained. Omit it in real use and
# the module co-locates the account with the resource group.
location = "eastus"

# Object ID of the application's Entra ID identity (managed identity or
# service principal) — gets Storage Blob Data Contributor on the account.
identity_principal_id = "11111111-1111-1111-1111-111111111111"

# Private blob containers to create for the app.
containers = ["uploads", "media", "reports"]

tags = {
  application = "orders"
  environment = "staging"
}
