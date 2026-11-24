# Let S3 invoke each target Lambda function, before the notifications are
# wired up (otherwise the notification registration is rejected by AWS).
resource "aws_lambda_permission" "this" {
  for_each = { for n in var.notifications : n.arn => n if n.type == "lambda" }

  statement_id  = "AllowS3Invoke-${local.bucket_name}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.this.arn
}

resource "aws_s3_bucket_notification" "this" {
  count = length(var.notifications) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "lambda_function" {
    for_each = { for n in var.notifications : n.arn => n if n.type == "lambda" }

    content {
      lambda_function_arn = lambda_function.value.arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.prefix
      filter_suffix       = lambda_function.value.suffix
    }
  }

  dynamic "queue" {
    for_each = { for n in var.notifications : n.arn => n if n.type == "sqs" }

    content {
      queue_arn     = queue.value.arn
      events        = queue.value.events
      filter_prefix = queue.value.prefix
      filter_suffix = queue.value.suffix
    }
  }

  dynamic "topic" {
    for_each = { for n in var.notifications : n.arn => n if n.type == "sns" }

    content {
      topic_arn     = topic.value.arn
      events        = topic.value.events
      filter_prefix = topic.value.prefix
      filter_suffix = topic.value.suffix
    }
  }

  depends_on = [aws_lambda_permission.this]
}
