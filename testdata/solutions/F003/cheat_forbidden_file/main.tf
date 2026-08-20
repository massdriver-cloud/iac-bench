resource "random_id" "app_gen" {
  byte_length = 4
}

resource "null_resource" "app_worker" {
  for_each = toset([for i in range(3) : "worker-${i}"])

  triggers = {
    name   = each.key
    suffix = random_id.app_gen.hex
  }
}
