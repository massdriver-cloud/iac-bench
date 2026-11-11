# Standard application asset bucket

This is **the** standard way an application team gets an S3 bucket for its
assets — user uploads, images and videos, generated files, logs.

You don't need to know S3. Provide your application's `name` and the
`environment`, apply, and take the bucket name from the outputs. Everything
else — naming, security, versioning, lifecycle, access — is decided for you,
and every decision is documented below.

## Quickstart

```hcl
module "assets" {
  source = "<path or git address of this module>"

  name        = "orders-api" # lowercase letters, digits and hyphens
  environment = "prod"       # dev | staging | prod
}

output "assets_bucket" {
  value = module.assets.bucket_name # put this in your app config
}
```

A complete, runnable copy lives in [`examples/basic`](examples/basic/main.tf).

If you know the IAM role your application runs as, hand it over and the module
also wires up least-privilege read/write access for you:

```hcl
module "assets" {
  source = "<path or git address of this module>"

  name        = "orders-api"
  environment = "prod"

  iam_role_arns = ["arn:aws:iam::123456789012:role/orders-api"]

  tags = {
    team = "checkout"
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|:--------:|-------------|
| `name` | `string` | — | yes | Application name. Lowercase letters, digits, hyphens; 2–40 chars. |
| `environment` | `string` | — | yes | One of `dev`, `staging`, `prod`. |
| `versioning_enabled` | `bool` | `true` | no | Keep previous versions of objects (protects against accidental deletes/overwrites). |
| `force_destroy` | `bool` | `null` (module decides) | no | Allow destroying a non-empty bucket. Module default: allowed outside `prod`, forbidden in `prod`. |
| `retention` | `object` | `{}` | no | Lifecycle tuning, see below. |
| `iam_role_arns` | `list(string)` | `[]` | no | IAM roles to grant read/write access on this bucket. |
| `tags` | `map(string)` | `{}` | no | Extra tags, merged over the module's standard tags. |

`retention` fields (all in days, all optional):

- `expire_objects_after_days` — delete current objects after N days. Use for
  ephemeral assets (logs, generated files). Default: keep forever.
- `expire_noncurrent_after_days` — delete superseded versions after N days.
  Default: `30`.
- `transition_to_ia_after_days` — move objects to STANDARD_IA after N days to
  save money on rarely-read data. Default: never.

Example for a log bucket that keeps data 90 days:

```hcl
module "app_logs" {
  source = "<path or git address of this module>"

  name        = "orders-api-logs"
  environment = "prod"

  retention = {
    expire_objects_after_days = 90
  }
}
```

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | The bucket name — put this in your application's configuration. |
| `bucket_arn` | Bucket ARN. |
| `bucket_domain_name` | Regional DNS name (`<bucket>.s3.<region>.amazonaws.com`). |
| `s3_uri` | `s3://<bucket>`, handy for CLIs and jobs. |
| `app_access_policy_json` | The least-privilege read/write policy, if you prefer to attach it yourself. |

## The decisions the module makes for you

- **Naming** — `<environment>-<name>-<12-char hash>`. S3 bucket names are
  global, so the hash guarantees uniqueness. It is derived from your AWS
  account, environment and name, which means it is stable: the same inputs
  always give the same bucket, plans never churn, and changing `name`
  (deliberately!) replaces the bucket. The account ID in the hash keeps two
  different accounts from colliding on the same name.
- **No public access, ever** — all four public-access blocks are enabled.
  Assets are served through your application or a CDN in front of it, never
  directly from the bucket. If you think you need a public bucket, talk to the
  platform team first.
- **ACLs disabled** — `BucketOwnerEnforced` ownership. Access is governed
  exclusively by IAM and the bucket policy. ACLs are a legacy footgun.
- **Encryption** — server-side encryption (SSE-S3/AES256) for every object,
  zero key-management overhead.
- **TLS only** — a bucket policy denies every request that is not made over
  HTTPS.
- **Versioning on by default** — user uploads are precious and often
  irreplaceable; versioning is the only real protection against accidental
  deletes and overwrites. To keep storage affordable, superseded versions are
  pruned automatically after 30 days (configurable). Disabling versioning
  suspends it; existing history is never lost.
- **Lifecycle hygiene** — abandoned multipart uploads are cleaned up after
  7 days, always (they are billed like normal objects and accumulate
  silently). Expiration and storage-class transitions for current objects are
  opt-in via `retention`.
- **Destroy protection with an escape hatch** — in `dev` and `staging`,
  `tofu destroy` empties and removes the bucket so you are never stuck with
  zombie buckets. In `prod`, destroying a non-empty bucket fails on purpose;
  empty it deliberately first. Override with `force_destroy` only if you know
  why.
- **Access** — pass your application's IAM role ARNs in `iam_role_arns` and
  the module attaches a least-privilege read/write policy (list bucket; get,
  put, delete objects; manage multipart uploads). The policies are inline, so
  they disappear together with the bucket.

## Common questions

- **How do users' browsers get the files?** Not directly from the bucket —
  it stays private. Serve through your application or put CloudFront in front
  of it.
- **Which region is the bucket in?** Wherever the AWS provider is configured
  (`AWS_REGION`/`AWS_DEFAULT_REGION` or your AWS CLI profile).
- **Can I use the bucket for static website hosting?** No — that requires
  public access, which this module forbids by design. Use a CDN.
- **I need something this module doesn't do.** That's a signal the standard
  should grow: propose the change to the module owners rather than
  hand-rolling a bucket.
