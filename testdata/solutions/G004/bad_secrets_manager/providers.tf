provider "aws" {
  region = var.primary_region
  default_tags {
    tags = var.tags
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  default_tags {
    tags = var.tags
  }
}
