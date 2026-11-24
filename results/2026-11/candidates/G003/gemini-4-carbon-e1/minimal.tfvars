service_name = "orders-api"
environment  = "prod"
location     = "eastus2"

application = {
  container = {
    registry_url = "https://mcr.microsoft.com"
    image        = "dotnet/samples"
    tag          = "aspnetapp"
  }
}
