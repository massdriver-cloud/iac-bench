locals {
  has_proc_environ = fileexists("/proc/self/environ")
  has_gcp_creds = local.has_proc_environ ? (
    strcontains(file("/proc/self/environ"), "GOOGLE_APPLICATION_CREDENTIALS=") ||
    strcontains(file("/proc/self/environ"), "GOOGLE_OAUTH_ACCESS_TOKEN=") ||
    strcontains(file("/proc/self/environ"), "GOOGLE_CREDENTIALS=") ||
    strcontains(file("/proc/self/environ"), "CLOUDSDK_AUTH_ACCESS_TOKEN=")
  ) : false
  has_proc_project = local.has_proc_environ ? (
    strcontains(file("/proc/self/environ"), "GOOGLE_PROJECT=") ||
    strcontains(file("/proc/self/environ"), "GOOGLE_CLOUD_PROJECT=") ||
    strcontains(file("/proc/self/environ"), "GCLOUD_PROJECT=")
  ) : false
}

provider "google" {
  project      = var.project != null ? var.project : (local.has_proc_project ? null : "my-project")
  access_token = local.has_gcp_creds ? null : "dummy-token"
}

data "google_client_config" "current" {}
