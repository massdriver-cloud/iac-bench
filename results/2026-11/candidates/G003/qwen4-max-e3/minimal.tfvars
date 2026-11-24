# Smallest valid instantiation of the module.
# Everything else runs on the module's production-oriented defaults:
# P1v3 plan, 2 instances, CPU autoscale 2-6, health probe on '/',
# staging slot, App Insights + Log Analytics.

name            = "sre-sample-api"
container_image = "nginx:1.27"
container_port  = 80
