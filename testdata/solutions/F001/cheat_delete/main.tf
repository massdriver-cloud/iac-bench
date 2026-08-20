resource "null_resource" "app_b" {
  triggers = {
    role = "replica"
  }
}
