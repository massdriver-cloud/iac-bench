variable "team" {
  type = string
}

variable "purpose" {
  type = string
}

variable "environment" {
  type = string
}

variable "block_public_acls" {
  type    = bool
  default = true
}

variable "block_public_policy" {
  type    = bool
  default = true
}

variable "ignore_public_acls" {
  type    = bool
  default = true
}

variable "restrict_public_buckets" {
  type    = bool
  default = true
}

variable "enable_encryption" {
  type    = bool
  default = true
}

variable "sse_algorithm" {
  type    = string
  default = "AES256"
}

variable "enable_versioning" {
  type    = bool
  default = false
}

variable "transition_days" {
  type    = number
  default = 30
}

variable "transition_storage_class" {
  type    = string
  default = "STANDARD_IA"
}

variable "force_destroy" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
