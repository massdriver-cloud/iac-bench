# Smallest valid instantiation of the standard App Service module.
# Every variable without a default gets a literal value here; everything else
# runs on the module's SRE defaults (zone-redundant P1v3 plan, health checks,
# staging slot, autoscale, Application Insights).

service_name    = "example-api"
environment     = "dev"
container_image = "nginx:stable"
