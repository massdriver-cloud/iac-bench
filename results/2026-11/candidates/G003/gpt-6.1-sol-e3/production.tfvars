name = "sre-api-example-7b29"
container = {
  image = "nginx:1.28-alpine"
  port  = 80
}
health_check_path     = "/"
alert_email_addresses = ["sre@example.com"]
