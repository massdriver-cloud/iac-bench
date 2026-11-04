bucket_name   = "my-test-app-bucket"
force_destroy = true

tags = {
  Environment = "production"
  Application = "media-service"
}

versioning_enabled = true

kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

logging_target_bucket = "company-s3-logs"
logging_target_prefix = "media-service/"

cors_rules = [
  {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["https://app.example.com"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
]

custom_lifecycle_rules = [
  {
    id     = "archive-raw-uploads"
    prefix = "raw/"
    transitions = [
      {
        days          = 30
        storage_class = "STANDARD_IA"
      },
      {
        days          = 90
        storage_class = "GLACIER"
      }
    ]
  }
]

custom_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowReadFromAppRole\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:role/AppRole\"},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::my-test-app-bucket/*\"}]}"
