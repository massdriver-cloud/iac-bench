# Smallest valid instantiation of the standard App Service module.
#
# Only `name`, `resource_group_name` and `location` are strictly required;
# the overrides below deliberately pick the cheapest tier that still
# exercises the full feature set (staging slot + autoscale) without needing
# Premium v3 quota.

name                = "sre-std-web"
resource_group_name = "rg-sre-std-web"
location            = "eastus"

sku_name                = "S1" # Standard: supports slots and autoscale
instance_count          = 1
autoscale_min_instances = 1
