variable "name" {
  description = "Cluster name, unique within the project and region."
  type        = string
}

variable "region" {
  description = "Region for the regional cluster."
  type        = string
}

variable "network" {
  description = "Name of the environment's VPC (apps-staging or apps-prod)."
  type        = string
}

variable "subnetwork" {
  description = "Name of the GKE subnet in the region (<vpc>-gke-<region>), with secondary ranges named pods and services."
  type        = string
}

variable "machine_type" {
  description = "Machine type of the cluster's node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "min_nodes_per_zone" {
  description = "Lower bound for node autoscaling, per zone."
  type        = number
  default     = 1
}

variable "max_nodes_per_zone" {
  description = "Upper bound for node autoscaling, per zone."
  type        = number
  default     = 5
}

variable "secrets_encryption_key" {
  description = "Cloud KMS key that encrypts Kubernetes Secrets in etcd. Before setting it, grant roles/cloudkms.cryptoKeyEncrypterDecrypter on the key to service-<project number>@container-engine-robot.iam.gserviceaccount.com; GKE rejects the key otherwise."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Refuse to destroy the cluster. Set false only to retire it."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to the cluster."
  type        = map(string)
  default     = {}
}
