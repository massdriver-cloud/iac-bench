# Smallest valid instantiation of the module: only the two required variables.
# Every other knob has a default tuned for a standard containerized HTTP API.
#
# nginx listens on :80 and serves "/" with a 200, so the module defaults
# (container_port = 80, health_probe_path = "/") give a passing health check.
name            = "demo-api"
container_image = "nginx:1.27-alpine"
