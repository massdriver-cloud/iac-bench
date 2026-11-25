# Smallest valid instantiation: where (the app's resource group), who (the
# app's identity) and what (the containers it needs).

resource_group_name = "orders-staging"

# Object ID of the application's identity in Entra ID. Replace with your own.
application_principal_id = "3a383881-29ae-4e10-84e4-d3cfe90a0ee9"

containers = {
  uploads = {}
}
