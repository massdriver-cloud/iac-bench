# Primary region: home of the writer under normal operation.
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

# Secondary (DR) region: hot standby cluster, promotion target on regional
# failure. Because this is consumed as a root module, both provider
# configurations are declared here and their regions are driven by
# variables, so the same code runs the whole two-region footprint.
provider "aws" {
  alias  = "dr"
  region = var.secondary_region

  default_tags {
    tags = local.common_tags
  }
}
