# A bucket for temporary browser uploads that are cleaned up after two weeks.
app_name    = "photo-service"
environment = "staging"
purpose     = "uploads"

cors_allowed_origins      = ["https://photos.example.com", "http://localhost:3000"]
expire_objects_after_days = 14

tags = {
  Team = "photos"
}
