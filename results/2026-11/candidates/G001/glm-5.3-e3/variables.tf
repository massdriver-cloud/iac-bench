###############################################################################
#
# Required input
#
###############################################################################

variable "name_prefix" {
  description = <<-EOT
    Short, lowercase name for your application or the assets it stores, e.g.
    "acme-uploads" or "billing-invoices".

    The module derives a unique, predictable bucket name from it:
    <name_prefix>-<aws_account_id>-<aws_region>, so you never have to invent a
    name or worry about it clashing with anyone else's in the world. If you run
    more than one bucket per account and region (e.g. dev and staging buckets
    in a shared account), distinguish them here, e.g. "acme-uploads-staging".

    1-35 characters, lowercase letters, digits and hyphens only; must start and
    end with a letter or digit.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,33}[a-z0-9])?$", var.name_prefix))
    error_message = "The name_prefix must be 1-35 characters long, may contain only lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }

  validation {
    condition     = !startswith(var.name_prefix, "xn--") && !startswith(var.name_prefix, "sthree-") && !startswith(var.name_prefix, "amzn-s3-demo-")
    error_message = "The name_prefix must not start with the reserved S3 prefixes \"xn--\", \"sthree-\" or \"amzn-s3-demo-\"."
  }
}

###############################################################################
#
# Optional inputs with safe defaults - only set these if you need to
#
###############################################################################

variable "tags" {
  description = "Tags applied to every resource this module creates (e.g. { team = \"payments\", cost-center = \"CC-123\" }). The module always also sets a Name tag with the bucket name; your tags win on conflicts."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = <<-EOT
    Allow the bucket to be destroyed even while it still contains objects.
    DANGEROUS: destroying will permanently delete every object in the bucket.
    Leave it false (the default) unless the bucket only ever holds throwaway
    data you are happy to lose (e.g. CI scratch space).
  EOT
  type        = bool
  default     = false
}

# --- Retention and lifecycle --------------------------------------------------

variable "versioning_enabled" {
  description = <<-EOT
    Keep every version of every object. Versioning is what makes overwrites and
    deletes recoverable, and is on by default. Only turn it off for buckets
    where you are certain no object is ever overwritten and nothing ever needs
    to be undeleted.
  EOT
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = <<-EOT
    How many days to keep an old (overwritten or deleted) version of an object
    before it is permanently removed and stops costing money. Set to 0 to keep
    old versions forever (e.g. audit/compliance buckets).
  EOT
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 0
    error_message = "The noncurrent_version_expiration_days must be 0 (never expire) or a positive number of days."
  }
}

variable "expire_objects_after_days" {
  description = <<-EOT
    Permanently delete objects this many days after they are uploaded. Default
    0 = keep forever. Use this for buckets of short-lived data such as temp
    files, scratch exports or rotating logs. (With versioning on, a deleted
    object's final version is then also cleaned up after
    noncurrent_version_expiration_days, so total retention is roughly this
    value plus that one.)
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.expire_objects_after_days >= 0
    error_message = "The expire_objects_after_days must be 0 (never expire) or a positive number of days."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = <<-EOT
    Remove the hidden storage of multipart uploads that were started but never
    finished (e.g. a crashed upload of a large video) after this many days.
    Without this, abandoned uploads keep costing money invisibly. Set to 0 to
    disable the cleanup.
  EOT
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 0
    error_message = "The abort_incomplete_multipart_upload_days must be 0 (disabled) or a positive number of days."
  }
}

variable "enable_intelligent_tiering" {
  description = <<-EOT
    Store objects in the S3 Intelligent-Tiering storage class from day one:
    anything nobody reads for 30 consecutive days automatically drops to a
    much cheaper tier, and moves back instantly (no retrieval fee, no
    performance change) the moment it is read again. Recommended for the
    long-lived assets most applications keep. AWS charges a small per-object
    transition request fee, so turn it off for buckets full of small,
    short-lived objects.
  EOT
  type        = bool
  default     = true
}

variable "archive_objects_after_days" {
  description = <<-EOT
    Additionally move objects nobody has accessed for this many days down to
    the S3 Glacier archive tier, for the cheapest storage of all. Opt in
    consciously: retrieving an archived object takes several hours. Good for
    data you are keeping "just in case"; bad for anything a user might
    request. 0 (the default) keeps every object instantly retrievable.
    Minimum 90 days (an S3 requirement).
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.archive_objects_after_days == 0 || var.archive_objects_after_days >= 90
    error_message = "The archive_objects_after_days must be 0 (disabled) or at least 90 (an S3 requirement for the archive tier)."
  }

  validation {
    condition     = var.archive_objects_after_days == 0 || var.enable_intelligent_tiering
    error_message = "Archiving relies on intelligent tiering; leave enable_intelligent_tiering = true, or set archive_objects_after_days = 0."
  }
}

# --- Encryption ---------------------------------------------------------------

variable "encryption" {
  description = <<-EOT
    How objects are encrypted at rest:
      "SSE-S3" (default) - encrypted with keys managed by S3 itself. No extra
                           cost, no permissions to wire up, every object
                           encrypted. The right choice for most application
                           assets.
      "SSE-KMS"          - encrypted with a KMS customer-managed key: you get a
                           key policy, per-key audit trail in CloudTrail, and
                           the ability to revoke access to everything in one
                           place. Costs a little more per request. The module
                           creates and auto-rotates a dedicated key for this
                           bucket unless you pass kms_key_arn.
  EOT
  type        = string
  default     = "SSE-S3"

  validation {
    condition     = contains(["SSE-S3", "SSE-KMS"], var.encryption)
    error_message = "The encryption must be \"SSE-S3\" or \"SSE-KMS\"."
  }
}

variable "kms_key_arn" {
  description = <<-EOT
    An existing KMS key to encrypt with when encryption = "SSE-KMS". Leave null
    to let the module create a dedicated, auto-rotating key for this bucket.
    Must be null when encryption = "SSE-S3" (it is not used).
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || var.encryption == "SSE-KMS"
    error_message = "The kms_key_arn is only used with encryption = \"SSE-KMS\"; set encryption = \"SSE-KMS\" or remove kms_key_arn."
  }
}

# --- Direct browser access ------------------------------------------------------

variable "cors_allowed_origins" {
  description = <<-EOT
    Origins of web apps that talk to this bucket directly from the browser
    (typically via presigned URLs), e.g. ["https://app.example.com"]. Leave
    empty (the default) if only your servers access the bucket. The module
    grants exactly these origins the minimum CORS needed to upload and
    download objects.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for origin in var.cors_allowed_origins : can(regex("^https?://", origin))])
    error_message = "Each entry in cors_allowed_origins must be an origin like \"https://app.example.com\" (scheme and host only, no path or trailing slash)."
  }
}

# --- Access logging ---------------------------------------------------------------

variable "access_log_target_bucket" {
  description = <<-EOT
    Name of an existing bucket that should receive S3 server access logs for
    this bucket (e.g. a central logging bucket owned by your platform team).
    Leave null (the default) to disable access logging. The target bucket must
    allow S3 log delivery to it - see
    https://docs.aws.amazon.com/AmazonS3/latest/userguide/enable-server-access-logging.html
  EOT
  type        = string
  default     = null
}

variable "access_log_target_prefix" {
  description = "Prefix (folder) under which this bucket's access logs are written in the target bucket. Defaults to \"<bucket-name>/\"."
  type        = string
  default     = null
}

# --- Event notifications ------------------------------------------------------------

variable "notifications" {
  description = <<-EOT
    React to changes in the bucket, e.g. process each file as it arrives.
    Each entry takes:
      type   - "lambda" (invoke an AWS Lambda function), "sqs" (enqueue to an
               SQS queue) or "sns" (publish to an SNS topic)
      arn    - the Lambda function / SQS queue / SNS topic ARN
      events - S3 events to react to, most commonly ["s3:ObjectCreated:*"]
               (object uploaded) or ["s3:ObjectRemoved:*"] (object deleted)
      prefix - (optional) only react to objects under this prefix, e.g. "incoming/"
      suffix - (optional) only react to objects with this suffix, e.g. ".jpg"

    Example:
      notifications = [{
        type   = "sqs"
        arn    = "arn:aws:sqs:us-west-2:123456789012:upload-events"
        events = ["s3:ObjectCreated:*"]
        prefix = "incoming/"
      }]

    Use one entry per destination (a destination can only be wired up once per
    bucket). The destination must live in the same AWS account and region as
    the bucket, and SQS/SNS destinations need a resource policy that lets
    s3.amazonaws.com deliver to them. For Lambda, the module sets up the
    required permission for you.
  EOT
  type = list(object({
    type   = string
    arn    = string
    events = list(string)
    prefix = optional(string)
    suffix = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.notifications : contains(["lambda", "sqs", "sns"], n.type)])
    error_message = "Each notification must have type \"lambda\", \"sqs\" or \"sns\"."
  }

  validation {
    condition     = alltrue([for n in var.notifications : length(n.events) > 0])
    error_message = "Each notification must list at least one S3 event, e.g. [\"s3:ObjectCreated:*\"]."
  }
}

# --- Ready-made application access ---------------------------------------------------

variable "create_app_access_policy" {
  description = <<-EOT
    Also create an IAM policy granting exactly what an application needs on
    this bucket (list it, and read/overwrite/delete its objects - plus use of
    the KMS key when encryption = "SSE-KMS"). Attach the resulting
    app_access_policy_arn output to your application's execution role.
    Default false: most teams already have their own way to wire up IAM.
  EOT
  type        = bool
  default     = false
}
