# Smallest valid instantiation of the standard App Service module:
# a single-instance B1 app running a public demo HTTP container.
# Production services should use the module defaults (P1v3 x3, staging slot).

service_name    = "demo-api"
location        = "westeurope"
container_image = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"

container_port = 80
sku_name       = "B1"
worker_count   = 1

# The demo image has no dedicated health endpoint; probe root.
health_check_path = "/"

# Slots require Standard or better; skip for the minimal footprint.
staging_slot_enabled = false
