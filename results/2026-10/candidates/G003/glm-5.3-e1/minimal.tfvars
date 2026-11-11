# Smallest valid instantiation of the module.
#
# Required inputs only: a name, a region, a container image, and an on-call
# email address (the module refuses to deploy an unmonitored service).

name            = "sre-hello-api-demo"
location        = "westeurope"
container_image = "nginx"
alert_emails    = ["sre@example.com"]

# The demo image has no /healthz endpoint; probe / so the health check,
# auto-heal and availability test all stay green on the demo app.
health_check_path = "/"
