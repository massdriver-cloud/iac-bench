# Smallest valid instantiation: everything else has a production-grade default.
name              = "orders-api"
environment       = "dev"
location          = "swedencentral"
image             = "mcr.microsoft.com/dotnet/samples:aspnetapp"
health_check_path = "/healthz"
