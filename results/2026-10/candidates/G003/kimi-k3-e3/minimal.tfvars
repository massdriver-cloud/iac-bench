# Smallest valid instantiation of the module: the required inputs only.
# Everything else rides on the module's defaults (P1v3 plan x2 workers,
# staging slot, health checks, auto-heal, Log Analytics + App Insights).
name                   = "sre-demo-api"
resource_group_name    = "rg-sre-demo-api"
location               = "westeurope"
container_image        = "appsvc/staticsite:latest"
container_registry_url = "https://mcr.microsoft.com"
