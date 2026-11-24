locals {
  monitoring_database_id = "${data.google_project.current.project_id}:${google_sql_database_instance.primary.name}"

  alert_policies = {
    cpu_high = {
      display_name = "Cloud SQL PostgreSQL [${local.instance_name}] - High CPU Utilization"
      condition    = "CPU utilization above 85% for 5 minutes"
      metric_type  = "cloudsql.googleapis.com/database/cpu/utilization"
      comparison   = "COMPARISON_GT"
      threshold    = 0.85
      duration     = "300s"
      aligner      = "ALIGN_MEAN"
      doc          = "CPU utilization on Cloud SQL instance `${local.instance_name}` has exceeded 85% for 5 minutes. Investigate slow queries in Query Insights or consider scaling tier."
    }
    memory_high = {
      display_name = "Cloud SQL PostgreSQL [${local.instance_name}] - High Memory Utilization"
      condition    = "Memory utilization above 90% for 5 minutes"
      metric_type  = "cloudsql.googleapis.com/database/memory/utilization"
      comparison   = "COMPARISON_GT"
      threshold    = 0.90
      duration     = "300s"
      aligner      = "ALIGN_MEAN"
      doc          = "Memory utilization on Cloud SQL instance `${local.instance_name}` has exceeded 90% for 5 minutes. Check active connections, work_mem, and shared_buffers."
    }
    disk_high = {
      display_name = "Cloud SQL PostgreSQL [${local.instance_name}] - High Disk Utilization"
      condition    = "Disk utilization above 85% for 5 minutes"
      metric_type  = "cloudsql.googleapis.com/database/disk/utilization"
      comparison   = "COMPARISON_GT"
      threshold    = 0.85
      duration     = "300s"
      aligner      = "ALIGN_MEAN"
      doc          = "Disk utilization on Cloud SQL instance `${local.instance_name}` has exceeded 85% for 5 minutes. Verify disk autoresize and check table/WAL bloat."
    }
    instance_down = {
      display_name = "Cloud SQL PostgreSQL [${local.instance_name}] - Instance Unavailable"
      condition    = "Database up metric below 1 for 2 minutes"
      metric_type  = "cloudsql.googleapis.com/database/up"
      comparison   = "COMPARISON_LT"
      threshold    = 1
      duration     = "120s"
      aligner      = "ALIGN_MIN"
      doc          = "Cloud SQL instance `${local.instance_name}` is reporting unavailable (`database/up < 1`) for 2 minutes."
    }
  }
}

resource "google_monitoring_alert_policy" "postgresql" {
  for_each = var.enable_monitoring_alerts ? local.alert_policies : {}

  display_name          = each.value.display_name
  combiner              = "OR"
  notification_channels = var.alert_notification_channels
  user_labels           = local.labels

  conditions {
    display_name = each.value.condition

    condition_threshold {
      filter          = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${local.monitoring_database_id}\" AND metric.type = \"${each.value.metric_type}\""
      comparison      = each.value.comparison
      threshold_value = each.value.threshold
      duration        = each.value.duration

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = each.value.aligner
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = each.value.doc
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s"
  }
}
