# Basic: the only two inputs an app team needs.

module "assets" {
  source      = "../.."
  name        = "user-uploads"
  environment = "dev"
}

output "bucket_name" {
  description = "The bucket this example creates."
  value       = module.assets.bucket_name
}
