# Smallest valid instantiation of the standard App Service module:
# one containerized HTTP API with everything else at its standard defaults
# (P1v3 plan, autoscale 2-10, staging slot, health checks, availability
# test, App Insights + Log Analytics).

service_name    = "orders-api-sre-std-01"
container_image = "azure-app-service/samples/python-hello-world:latest"
