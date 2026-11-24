# Default production capacity and staging. Replace the example name and image.
name            = "sre-api-production-7c91e4"
location        = "eastus"
container_image = "nginx:1.28.0"

# Enable only after checking region support and subscription capacity:
# zone_redundant = true
# alert_email_addresses = ["oncall@example.com"]

# For real APIs use an unauthenticated dependency-aware endpoint:
# health_check_path = "/ready"
# container_port    = 8080

# Prefer separate dependencies for staging.
app_settings = {
  SERVICE_ENVIRONMENT = "production"
}
staging_app_settings = {
  SERVICE_ENVIRONMENT = "staging"
}

tags = {
  owner       = "sre"
  environment = "production"
}
