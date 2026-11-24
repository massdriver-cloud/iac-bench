check "distinct_regions" {
  assert {
    condition     = var.primary_region != var.secondary_region
    error_message = "primary_region and secondary_region must be distinct AWS regions to ensure cross-region Global Database disaster recovery."
  }
}

check "primary_database_subnets_multi_az" {
  assert {
    condition     = length(data.aws_subnets.primary_database.ids) >= 2
    error_message = "At least 2 private database subnets (tagged tier = database) must exist in the primary region VPC (apps-${var.environment})."
  }
}

check "secondary_database_subnets_multi_az" {
  assert {
    condition     = length(data.aws_subnets.secondary_database.ids) >= 2
    error_message = "At least 2 private database subnets (tagged tier = database) must exist in the secondary region VPC (apps-${var.environment})."
  }
}
