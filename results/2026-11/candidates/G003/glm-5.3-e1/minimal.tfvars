# Smallest valid instantiation of the SRE App Service module.
#
# Runs a public demo image on the module's defaults: P1v3 Linux plan, CPU
# autoscaling between 2 and 6 instances, health check on "/", staging slot,
# dedicated Log Analytics workspace, Application Insights, and platform log
# collection. Baseline alerts are dormant because no alert_emails are set.
#
# For a real service, at minimum change:
#   name            -> the service's name (must be globally unique: <name>.azurewebsites.net)
#   location        -> your region
#   container_image -> your registry/image:tag, with acr_resource_id for ACR

name            = "sre-demo-api"
location        = "eastus"
container_image = "nginxdemos/hello:latest"
