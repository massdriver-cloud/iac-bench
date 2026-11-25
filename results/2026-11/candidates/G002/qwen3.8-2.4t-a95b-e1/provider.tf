# Credentials come from the environment (GOOGLE_CREDENTIALS / ADC).
# The region follows the instance's region so every instantiation is
# self-contained.
provider "google" {
  region = var.region
}
