service_name = "orders-api"
environment  = "dev"
location     = "eastus2"

container = {
  image = "azuredocs/containerapps-helloworld:latest"
  port  = 80
}
