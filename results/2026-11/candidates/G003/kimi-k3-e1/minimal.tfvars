# Smallest valid instantiation of the module: the four required inputs,
# plus container_port because this sample image listens on 80.
# Everything else (SKU, capacity, zone redundancy, staging slot, autoscale,
# health checks, monitoring) uses the module's standard SRE defaults.

name                = "sre-sample-api"
resource_group_name = "rg-sre-sample"
location            = "westeurope"

image          = "appsvc/staticsite:latest"
container_port = 80
