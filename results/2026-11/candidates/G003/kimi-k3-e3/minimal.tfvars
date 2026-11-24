# Smallest valid instantiation of the standard App Service module.
# Everything not set here falls back to the module's standard defaults.

name                = "sre-stdapp-minimal"
resource_group_name = "rg-sre-stdapp-minimal"
location            = "westeurope"

container_image = "azuredocs/containerapps-helloworld:latest"
container_port  = 8080

# Cheapest tier that still supports the module's standard features
# (deployment slots and autoscaling require Standard or higher).
plan_sku         = "S1"
zone_redundant   = false
min_capacity     = 1
default_capacity = 1
max_capacity     = 2

# The sample image answers 200 on "/"; a real service should expose a
# dedicated health endpoint and use the default "/healthz".
health_check_path = "/"
