# User-uploaded images and videos: the browser uploads directly with pre-signed
# URLs, the API role manages files, and the public reads through CloudFront.
application = "photo-service"
environment = "prod"
purpose     = "media"

read_write_role_names = ["photo-service-api"]
read_only_role_names  = ["photo-service-thumbnailer"]

cors_allowed_origins         = ["https://photos.example.com"]
cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/E2ABCDEFGHIJKL"]

tags = {
  Team = "photos"
}
