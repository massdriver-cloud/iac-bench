# A cheap, single-instance development deployment: no zone redundancy,
# no autoscaling headroom, no staging slot, no alerts.
name              = "orders-api"
environment       = "dev"
location          = "swedencentral"
image             = "mcr.microsoft.com/dotnet/samples:aspnetapp"
health_check_path = "/healthz"

sku_name             = "P0v3"
min_instances        = 1
max_instances        = 1
zone_redundant       = false
staging_slot_enabled = false
alerts_enabled       = false
