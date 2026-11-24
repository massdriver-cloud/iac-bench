# Smallest valid instantiation of the module: the standard tier running a
# public sample container from the Microsoft registry (no ACR, no VNet, one
# staging slot, 3 zone-redundant P1v3 instances, default autoscale).
name              = "sre-sample-api"
location          = "eastus"
container_image   = "azuredocs/aks-helloworld:v1"
container_port    = 80
health_check_path = "/"
