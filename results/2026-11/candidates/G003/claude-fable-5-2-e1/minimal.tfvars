# Smallest valid instantiation: every other input has a production-grade default.
name              = "orders-api-dev"
location          = "eastus2"
image             = "mcr.microsoft.com/dotnet/samples:aspnetapp" # public sample; listens on 8080 and serves /healthz
health_check_path = "/healthz"
