locals {
  aws_account_id = data.aws_caller_identity.current.account_id

  # Stable, globally-unique bucket name:
  #   <environment>-<name>-<12-char hash of account/environment/name>
  #
  # S3 bucket names are global, so the hash protects against collisions with
  # other accounts (which we cannot see or control). Hashing the account ID
  # plus environment plus name means every account gets its own suffix while
  # a given team always gets the same name for the same inputs — plans never
  # churn and nothing is ever accidentally replaced.
  bucket_name = "${var.environment}-${var.name}-${substr(sha1("${local.aws_account_id}/${var.environment}/${var.name}"), 0, 12)}"

  # Developers must be able to tear down throwaway environments without first
  # emptying a bucket by hand; production data must never be deleted by a
  # careless `destroy`. Hence: force-destroy outside prod unless told
  # otherwise.
  force_destroy = coalesce(var.force_destroy, var.environment != "prod")

  common_tags = merge(
    {
      environment = var.environment
      application = var.name
      managed-by  = "opentofu"
    },
    var.tags,
  )

  # The "current objects" lifecycle rule only exists when the user asked for
  # an expiration or a storage-class transition.
  manage_current_objects = var.retention.expire_objects_after_days != null || var.retention.transition_to_ia_after_days != null
}
