# ---- Rollouts --------------------------------------------------------------

variable "slot_enabled" {
  description = "Provision a staging deployment slot for blue/green (swap) rollouts."
  type        = bool
  default     = true
}