# The primary cluster uses AWS Secrets Manager-managed master user credentials.
# No separate password provider is required; application access is via IAM
# database authentication, while the managed secret is used only for
# break-glass administrative access.