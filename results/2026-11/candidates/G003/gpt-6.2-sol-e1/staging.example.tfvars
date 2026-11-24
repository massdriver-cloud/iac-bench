# Illustrative values: replace the name, resource IDs, image and CIDR before applying.
name     = "orders-api-prod-example"
location = "eastus2"

container = {
  registry_url = "https://exampleregistry.azurecr.io"
  acr_id       = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-platform/providers/Microsoft.ContainerRegistry/registries/exampleregistry"
  image        = "orders/api:1.4.0"
}

capacity = {
  minimum        = 2
  maximum        = 6
  zone_redundant = true
}

app_settings = { APP_ENVIRONMENT = "production" }

staging = {
  image         = "orders/api:1.5.0"
  allowed_cidrs = ["192.0.2.0/24"]
  app_settings  = { APP_ENVIRONMENT = "staging" }
}

sticky_app_setting_names = ["APP_ENVIRONMENT"]

action_group_ids = ["/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-platform/providers/Microsoft.Insights/actionGroups/sre"]

tags = { service = "orders", environment = "production" }
