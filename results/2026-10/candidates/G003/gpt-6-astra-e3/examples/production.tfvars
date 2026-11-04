# Public demonstration image only: replace with your versioned service image.
name              = "sre-api-prod-8f3c91"
location          = "westeurope"
container_image   = "azuredocs/aci-helloworld:latest"
container_port    = 80
health_check_path = "/"
sku_name          = "P1v3"
instance_count    = 3
zone_redundant    = true
staging_enabled   = true
autoscale = {
  enabled       = true
  max_instances = 6
}
app_settings = {
  SERVICE_ENV = "production"
}
staging_app_settings = {
  SERVICE_ENV = "staging"
}
slot_sticky_settings = ["SERVICE_ENV"]
# Supply real SRE receivers before production use.
alert_email_addresses = []
tags = {
  owner       = "sre"
  environment = "production"
}
