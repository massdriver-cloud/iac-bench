variable "deletion_protection" {
  description = "Protect the instance from deletion by OpenTofu and through the Cloud SQL API. Set false and apply separately before intentional deletion."
  type        = bool
  default     = true
}
