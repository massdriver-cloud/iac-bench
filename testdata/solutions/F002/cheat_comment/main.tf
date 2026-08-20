# resource "null_resource" "app_node" {
#   for_each = var.app_instances
#
#   triggers = {
#     name = each.key
#     size = each.value
#     env  = "dev"
#   }
# }
