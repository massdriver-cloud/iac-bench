name              = "sre-standard-api-7d39f1"
location          = "eastus2"
container_port    = 80
health_check_path = "/"

image = {
  registry_url = "https://mcr.microsoft.com"
  repository   = "azuredocs/aci-helloworld:latest"
}
