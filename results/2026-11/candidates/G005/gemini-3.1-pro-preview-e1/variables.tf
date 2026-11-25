variable "project_id" {
  type        = string
  description = "The ID of the project to deploy the cluster into."
}

variable "region" {
  type        = string
  description = "The region to deploy the cluster into."
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
}

variable "vpc_name" {
  type        = string
  description = "The name of the VPC network to attach the cluster to. Subnet will be inferred as <vpc_name>-gke-<region>."
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "The IP range in CIDR notation to use for the hosted master network. Must be a /28."
}

variable "deletion_protection" {
  type        = bool
  description = "Whether or not to allow Terraform to destroy the cluster."
  default     = false
}

variable "machine_type" {
  type        = string
  description = "The machine type for the default node pool."
  default     = "e2-standard-4"
}
