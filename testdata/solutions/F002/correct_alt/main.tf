resource "null_resource" "app_node" {
  for_each = toset(var.app_instances)

  triggers = {
    name = each.value
    size = each.value
    env  = "dev"
  }
}
