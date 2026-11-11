name              = "sre-demo-api-7319"
location          = "westeurope"
container_image   = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
container_port    = 80
health_check_path = "/"

# The sample image is public, so it needs neither ACR permissions nor credentials.
container_registry_url                  = "https://mcr.microsoft.com"
container_registry_use_managed_identity = false
