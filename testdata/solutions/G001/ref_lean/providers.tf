provider "aws" {
  region = var.region

  # Every resource the module creates carries the same tags through one setting.
  default_tags {
    tags = local.tags
  }
}
