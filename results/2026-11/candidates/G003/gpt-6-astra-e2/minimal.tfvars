# Replace the name with a globally unique name and use a real monitored mailbox.
name                  = "sre-api-example-7f3c91"
container_image       = "azuredocs/aci-helloworld:latest"
alert_email_addresses = ["sre@example.com"]

# This public demonstration container serves HTTP on port 80 at /.
# Production services should use immutable images and a real readiness endpoint.
container_port    = 80
health_check_path = "/"
