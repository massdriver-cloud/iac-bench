# Smallest valid instantiation of the module: one instance per region and
# no deletion safeguards, suitable for evaluating the module itself. Every
# other input uses its production-oriented default.

name             = "checkout"
primary_region   = "us-east-1"
secondary_region = "us-west-2"

instance_class           = "db.r6g.large"
primary_instance_count   = 1
secondary_instance_count = 1

deletion_protection = false
skip_final_snapshot = true
