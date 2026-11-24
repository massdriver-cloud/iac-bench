name                = "sre-sample-api"
resource_group_name = "rg-sre-sample"
location            = "eastus"

# Public sample image; no registry credentials are required.
container_image        = "mcr.microsoft.com/dotnet/samples:aspnetapp"
container_registry_url = "https://mcr.microsoft.com"
container_port         = 8080
health_check_path      = "/"
