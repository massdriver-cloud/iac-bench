resource "null_resource" "app_worker" {
  for_each = toset(["worker-0", "worker-1", "worker-2"])

  triggers = {
    name = each.key
  }
}
