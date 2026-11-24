# Smallest valid instantiation of the SRE App Service module:
# a public nginx container, paged to one on-call address, serving "/" as its
# health probe (nginx has no /health endpoint).

name              = "sre-standard-web-7c2f"
location          = "westeurope"
container_image   = "nginx"
alert_emails      = ["sre-oncall@example.com"]
health_probe_path = "/"
