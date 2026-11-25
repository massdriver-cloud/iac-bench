terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      # >= 5.100 for the renamed RDS arguments used in this module
      # (e.g. iam_database_authentication_enabled).
      source  = "hashicorp/aws"
      version = ">= 5.100.0, < 6.0.0"
    }
  }
}
