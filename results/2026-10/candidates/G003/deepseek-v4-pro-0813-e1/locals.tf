# ------------------------------------------------------------------------------
# Local values
# ------------------------------------------------------------------------------

locals {
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "tofu-sre-appservice"
    },
    var.tags,
  )

  app_name = "${var.name}-${var.environment}"

  # Split "registry/repo/image:tag" into image reference + tag.
  # If no tag was supplied, default to "latest".
  image_parts       = split(":", var.docker_image)
  docker_image_name = length(local.image_parts) > 1 ? join(":", slice(local.image_parts, 0, length(local.image_parts) - 1)) : var.docker_image
  docker_image_tag  = length(local.image_parts) > 1 ? local.image_parts[length(local.image_parts) - 1] : "latest"
}