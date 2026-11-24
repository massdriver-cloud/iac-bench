name                      = "sre-example-slots-48291"
location                  = "eastus"
enable_staging_slot       = true
container_registry_url    = "https://example.azurecr.io"
container_image           = "service:production"
staging_container_image   = "service:candidate"
acr_resource_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/registry-rg/providers/Microsoft.ContainerRegistry/registries/example"
health_check_path         = "/healthz"
slot_sticky_setting_names = ["ENVIRONMENT"]
app_settings              = { ENVIRONMENT = "production" }
staging_app_settings      = { ENVIRONMENT = "staging" }
