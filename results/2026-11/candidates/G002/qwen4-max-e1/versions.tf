terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 7.0"
    }
  }
}

# The Google provider is configured by the platform for the project that
# owns the apps-{dev,staging,prod} networks. Instances are created in that
# same project; this module deliberately does not configure a provider or
# accept a project override.
