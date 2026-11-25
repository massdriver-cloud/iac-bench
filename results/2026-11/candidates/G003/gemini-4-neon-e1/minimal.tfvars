service_name = "orders-api"
environment  = "prod"
location     = "eastus2"

container = {
  image        = "appsvc/staticsite:latest"
  registry_url = "https://mcr.microsoft.com"
  port         = 8080
}
