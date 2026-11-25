# Smallest valid instantiation of the module.
#
# Four required inputs: name, location, image_name, image_tag.
# Everything else is a module default (see variables.tf / README.md).

name     = "sre-std-demo-api"
location = "westeurope"

# Public demo image from MCR (module default registry).
image_name = "azuredocs/aci-helloworld"
image_tag  = "latest"

# The demo image only serves "/", so point the health probe there.
health_check_path = "/"
