resource "aws_s3_bucket" "assets" {
  bucket = "acme-${var.team}-${var.purpose}"

  tags = {
    team        = var.team
    environment = var.environment
  }
}
