provider "google" {
  region         = var.region
  default_labels = local.labels
}
