# Smallest valid instantiation: literal values for every variable that has no
# default. Everything else (capacity, availability, health, rollouts,
# observability) falls back to the module's standard production defaults.
service_name        = "sre-ref-payments-api"
resource_group_name = "rg-sre-ref-payments-api"
location            = "westeurope"
container_image     = "nginx:1.27-alpine"
