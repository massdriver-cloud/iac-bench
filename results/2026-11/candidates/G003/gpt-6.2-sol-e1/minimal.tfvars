name        = "sre-api-example-7c21d4"
location    = "eastus2"
health_path = "/"
container = {
  image        = "azuredocs/aci-helloworld:latest"
  registry_url = "https://mcr.microsoft.com"
  port         = 80
}
