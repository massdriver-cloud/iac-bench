# Smallest valid instantiation: everything else uses production-safe defaults
# (us-east-1 primary, us-west-2 DR, db.r6g.large x2 per region, 35-day PITR,
# CMK encryption, enforced TLS, IAM auth, deletion protection).
service_name = "checkout"
environment  = "prod"
