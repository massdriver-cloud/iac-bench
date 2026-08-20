"""Find (and optionally delete) leaked iacbench-tagged AWS resources.

Every Tier-2 fixture tags its resources `iacbench=true` via provider
default_tags, and every scored attempt ends in `tofu destroy` — so this is a
backstop for crashes and interrupted runs, not the primary cleanup path.

Exit code 0 means the account is clean; non-zero means something is (still)
there, which makes this usable as a scheduled check.
"""

from __future__ import annotations

TAG_KEY = "iacbench"
TAG_VALUE = "true"


def run_sweep(region: str, delete: bool) -> int:
    import boto3

    tagging = boto3.client("resourcegroupstaggingapi", region_name=region)
    arns: list = []
    paginator = tagging.get_paginator("get_resources")
    for page in paginator.paginate(TagFilters=[{"Key": TAG_KEY, "Values": [TAG_VALUE]}]):
        arns.extend(r["ResourceARN"] for r in page["ResourceTagMappingList"])

    if not arns:
        print(f"no {TAG_KEY}={TAG_VALUE} tagged resources found in {region}")
        return 0

    for arn in arns:
        print(arn)
    if not delete:
        print(f"\n{len(arns)} leaked resource(s) found; re-run with --delete to remove supported types")
        return 1

    s3 = boto3.resource("s3", region_name=region)
    remaining = 0
    for arn in arns:
        try:
            if arn.startswith("arn:aws:s3:::"):
                bucket = s3.Bucket(arn.split(":::", 1)[1])
                bucket.objects.all().delete()
                bucket.object_versions.delete()
                bucket.delete()
                print(f"deleted {arn}")
            else:
                print(f"SKIP (type not handled by sweep yet — delete manually): {arn}")
                remaining += 1
        except Exception as exc:  # keep sweeping; report at the end
            print(f"FAILED to delete {arn}: {exc}")
            remaining += 1
    return 1 if remaining else 0
