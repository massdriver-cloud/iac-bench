resource "terraform_data" "app_link" {
  input = "app-link"
}

resource "null_resource" "app_a" {
  triggers = {
    peer = terraform_data.app_link.output
    role = "primary"
  }
}

resource "null_resource" "app_b" {
  triggers = {
    peer = terraform_data.app_link.output
    role = "replica"
  }
}
