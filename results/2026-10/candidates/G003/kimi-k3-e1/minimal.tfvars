# Smallest valid instantiation: every variable without a default gets a literal
# value here. Everything else (slots, health checks, alerts, App Insights, ...)
# is the module's standard, production-ready behaviour.
name                = "sample-api"
resource_group_name = "rg-sample-api"
location            = "eastus"

container = {
  # Public sample image from the Microsoft Container Registry.
  image = "azuredocs/aks-helloworld:v1"
}

# The sample image serves 200 on "/" but has no "/health" endpoint; real
# services keep the module default ("/health").
health_check_path = "/"

tags = {
  environment = "dev"
  team        = "sre"
}
