#!/usr/bin/env python3
"""Connection recipe, not a connection pool. Requires boto3 and workload IAM.

Usage: python discover-writer.py GLOBAL_ID DB_USER DATABASE us-west-2 us-east-1
Prints non-secret libpq connection settings. Never prints an IAM token. In an
application, cache briefly, rediscover after connection/write failures, and call
boto3.client('rds', region_name=region).generate_db_auth_token(...) immediately
before opening a TLS connection. Tokens expire in 15 minutes; existing sessions
are unaffected. Reconnect with bounded, jittered exponential backoff.
"""
import json
import sys
import time

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError


def discover(global_id, regions):
    config = Config(connect_timeout=3, read_timeout=5, retries={"max_attempts": 1})
    for region in regions:
        try:
            global_db = boto3.client("rds", region_name=region, config=config).describe_global_clusters(
                GlobalClusterIdentifier=global_id
            )["GlobalClusters"][0]
            if global_db["Status"] != "available":
                continue
            writers = [m for m in global_db["GlobalClusterMembers"] if m["IsWriter"]]
            if len(writers) != 1:
                continue
            arn = writers[0]["DBClusterArn"]
            writer_region = arn.split(":")[3]
            cluster = boto3.client("rds", region_name=writer_region, config=config).describe_db_clusters(
                DBClusterIdentifier=arn
            )["DBClusters"][0]
            if cluster["Status"] == "available":
                return writer_region, cluster["Endpoint"], cluster["Port"]
        except (BotoCoreError, ClientError, KeyError, IndexError):
            continue
    raise RuntimeError("No available global writer found; retry, never write to a stale cached reader")


if __name__ == "__main__":
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    global_id, user, database, *regions = sys.argv[1:]
    for attempt in range(6):
        try:
            region, host, port = discover(global_id, regions)
            print(json.dumps({"host": host, "port": port, "user": user, "dbname": database,
                              "sslmode": "verify-full", "sslrootcert": "global-bundle.pem",
                              "iam_token_region": region}))
            break
        except RuntimeError:
            if attempt == 5:
                raise
            time.sleep(min(2 ** attempt, 10))
