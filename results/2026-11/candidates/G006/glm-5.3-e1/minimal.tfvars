# Smallest valid instantiation of the module.
#
#   resource_group_name and identity_object_ids are the two things only the
#   app team can know; `containers` names the blobs the app works with. Every
#   other decision (naming, redundancy, security, data protection, lifecycle)
#   is made by the module.
resource_group_name = "orders-staging"

identity_object_ids = [
  "01234567-89ab-cdef-0123-456789abcdef",
]

# Location is optional (it defaults to the resource group's location) but is
# pinned here so this file plans without reading anything from Azure.
location = "westeurope"

containers = [
  {
    name = "app-files"
  },
]
