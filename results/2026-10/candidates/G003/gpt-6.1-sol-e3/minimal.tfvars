name = "sre-web-example-7b29"
container = {
  image = "nginx:1.28-alpine"
  port  = 80
}
health_check_path = "/"
capacity = {
  default_instances = 1
  min_instances     = 1
  max_instances     = 1
  autoscale_enabled = false
}
staging_enabled = false
