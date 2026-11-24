# The instance lives in the project that owns the apps-* VPC networks, and
# the Google provider is configured for that project. The module states the
# project explicitly (var.project) so that nothing about "which project"
# depends on ambient configuration, and passes it to every resource.
provider "google" {
  project = var.project
}
