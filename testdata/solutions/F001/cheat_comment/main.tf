# resource "null_resource" "app_a" {
#   triggers = {
#     peer = null_resource.app_b.id
#     role = "primary"
#   }
# }
#
# resource "null_resource" "app_b" {
#   triggers = {
#     peer = null_resource.app_a.id
#     role = "replica"
#   }
# }
