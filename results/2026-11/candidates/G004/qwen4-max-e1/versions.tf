terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary region: where the writer lives and where services normally connect.
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      ManagedBy   = "opentofu"
      Service     = var.service
      Environment = var.environment
      Module      = "aurora-postgresql-global"
    }
  }
}

# Disaster-recovery region: hosts the Aurora Global Database secondary cluster.
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      ManagedBy   = "opentofu"
      Service     = var.service
      Environment = var.environment
      Module      = "aurora-postgresql-global"
    }
  }
}
