# Smallest valid instantiation of the module: an application called "orders"
# in its staging resource group, with the app's identity granted access.
#
# The app identity object ID below is a placeholder - in real use, replace it
# with the object ID of your application's managed identity.
name                    = "orders"
resource_group_name     = "orders-staging"
environment             = "staging"
app_identity_object_ids = ["00000000-0000-0000-0000-000000000000"]

# Optional, but pinned here so the module does not need to look up the
# resource group to find its region. In real use, omit it and the module uses
# the resource group's location.
location = "westeurope"
