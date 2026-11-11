# Smallest valid instantiation of the standard App Service module: a public
# container image, everything else at module defaults (P1v3, zone-redundant,
# 3-6 autoscaled instances, /healthz health check, staging slot, dedicated
# Log Analytics workspace + App Insights).
name     = "sre-demo-api-6f31"
location = "westeurope"

image = {
  name = "nginx"
  tag  = "1.27"
}

# The stock nginx image has no /healthz endpoint, so the health check probes /.
health = {
  path = "/"
}
