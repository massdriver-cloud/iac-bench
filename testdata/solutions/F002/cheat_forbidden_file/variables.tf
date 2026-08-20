variable "app_instances" {
  description = "Map of instance name to size for the dev environment."
  type        = map(string)
  default = {
    web    = "small"
    api    = "medium"
    worker = "large"
  }
}
