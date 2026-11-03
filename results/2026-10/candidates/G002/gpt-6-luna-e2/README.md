# Standard Cloud SQL for PostgreSQL

This is a standalone OpenTofu root module for one private-IP Cloud SQL PostgreSQL instance and one application database. It uses the pre-existing `apps-dev`, `apps-staging`, or `apps-prod` VPC and does not create or modify networking.

## Required inputs

Set `project_id`, `instance_name`, `region`, `environment`, `database_name`, and the DBA-selected `tier`. `minimal.tfvars` shows the smallest valid configuration. For Shared VPC, set `network_project_id` to the host project; otherwise the instance project is used.

## Standard configuration

The module enforces private IP only, encrypted client connections, regional (HA) availability, SSD storage with autoresize, automated backups and seven-day PITR/log retention, query insights, stable-channel maintenance, and Cloud SQL IAM database authentication. Deletion protection is enabled by default. PostgreSQL defaults to version 16; DBAs can select another supported version and tune workload flags, disk sizing, maintenance window, and labels.

The selected VPC must already have Private Services Access configured and the Cloud SQL Admin API must be enabled. The identity running OpenTofu needs permission to manage Cloud SQL instances, databases, and users. IAM database users can be passed in `iam_database_users`; their Cloud SQL IAM database usernames and types must follow Cloud SQL's requirements. This module creates database principals but intentionally does not grant project IAM roles. The identity/security team must separately grant the connecting identities the appropriate Cloud SQL connection and `cloudsql.instances.login` permissions.
