# This module is intended to be applied directly as a root module, so it
# configures its own AWS provider. Credentials are picked up from the
# standard ambient sources (environment variables, shared config, task/
# instance role); the region comes from var.region, which defaults to the
# ambient AWS_REGION when left unset.
provider "aws" {
  region = var.region
}
