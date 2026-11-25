# Development-only example: reduced availability, no staging or public probes.
# Replace reserved example CIDRs with real trusted client/operator egress CIDRs.
# Run from the root: tofu plan -var-file=examples/allowlisted.tfvars
name                  = "sre-api-restricted-7f3c91"
container_image       = "azuredocs/aci-helloworld:latest"
alert_email_addresses = ["sre@example.com"]
container_port        = 80
health_check_path     = "/"

capacity = {
  minimum        = 1
  maximum        = 2
  zone_redundant = false
}
enable_staging_slot             = false
enable_public_availability_test = false
ingress_cidrs                   = ["192.0.2.0/24"]
management_cidrs                = ["198.51.100.10/32"]
tags                            = { environment = "development", owner = "sre" }
