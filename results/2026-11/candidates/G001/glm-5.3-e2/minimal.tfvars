# Minimal instantiation of the standard bucket module.
#
# `name` and `environment` are the only inputs an app team has to provide;
# every other decision is made by the module. This plans a private, SSE-S3
# encrypted, HTTPS-only, versioned bucket named
# app-assets-<environment>-<aws account id>.

name        = "app-assets"
environment = "dev"
