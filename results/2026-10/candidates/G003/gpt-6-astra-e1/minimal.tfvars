name            = "sre-api-minimal-7c91e4"
location        = "eastus"
container_image = "nginx:1.28.0"

# Smallest supported footprint: one dedicated worker and no staging slot.
# Production defaults instead provide two workers, CPU autoscaling and staging.
capacity = {
  autoscale_enabled = false
  minimum           = 1
  maximum           = 1
}
staging = {
  enabled = false
}
