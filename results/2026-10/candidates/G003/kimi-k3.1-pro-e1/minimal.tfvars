name                = "sre-demo-api-4c9e7b21"
resource_group_name = "rg-sre-demo-api-4c9e7b21"
location            = "eastus2"
container_image     = "appsvc/staticsite:latest"

# The sample image serves its home page rather than an API /health endpoint.
health_check_path = "/"
container_port    = 80
