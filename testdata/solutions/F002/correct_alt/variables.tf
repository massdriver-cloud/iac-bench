variable "app_instances" {
  description = "Instance sizes for the dev environment."
  type        = list(string)
  default     = ["small", "medium", "large"]
}
