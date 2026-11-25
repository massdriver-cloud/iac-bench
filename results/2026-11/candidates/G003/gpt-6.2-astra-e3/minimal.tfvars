service_name = "sre-api-starter-4c70f9"
container = {
  registry_url = "https://mcr.microsoft.com"
  image        = "azuredocs/aci-helloworld:latest"
  port         = 80
}
health_path = "/"
