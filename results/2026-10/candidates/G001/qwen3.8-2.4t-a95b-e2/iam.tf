# ---------------------------------------------------------------------------
# Application access
#
# One least-privilege policy covers the whole workflow: listing the bucket,
# reading/writing/deleting objects and managing multipart uploads (SDKs use
# multipart automatically for larger files).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "app_access" {
  statement {
    sid     = "BrowseBucket"
    actions = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.this.arn,
    ]
  }

  statement {
    sid = "ReadWriteObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = [
      "${aws_s3_bucket.this.arn}/*",
    ]
  }
}

# If the team told us which roles the application runs as, wire the policy up
# for them. The policy is inline so it is removed automatically together with
# the bucket — no orphaned IAM left behind.
resource "aws_iam_role_policy" "app_access" {
  for_each = toset(var.iam_role_arns)

  name   = "${aws_s3_bucket.this.bucket}-rw"
  role   = regex("([^/]+)$", each.value)[0]
  policy = data.aws_iam_policy_document.app_access.json
}
