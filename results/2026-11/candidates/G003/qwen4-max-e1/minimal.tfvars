# Smallest valid instantiation of the standard App Service module:
# a public container (nginx) with all opinionated defaults in place.

name            = "sre-standard-demo-api"
location        = "westeurope"
container_image = "nginx:alpine"

# nginx listens on 80 and serves / — override the module's API defaults.
container_port    = 80
health_check_path = "/"
