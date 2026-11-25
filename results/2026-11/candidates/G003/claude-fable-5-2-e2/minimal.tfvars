# Smallest valid instantiation: everything else uses the module's defaults.
name        = "orders-api"
environment = "dev"
location    = "westeurope"

image = {
  registry   = "mcr.microsoft.com"
  repository = "dotnet/samples"
  tag        = "aspnetapp"
}
