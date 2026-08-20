resource "random_id" "app_gen" {
  byte_length = 4
}

resource "null_resource" "app_worker" {
  count = 3

  triggers = {
    name   = "worker-${count.index}"
    suffix = random_id.app_gen.hex
  }
}
