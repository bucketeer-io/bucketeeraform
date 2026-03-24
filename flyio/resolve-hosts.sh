#!/bin/sh
# Pre-resolve Fly.io .internal hostnames into /etc/hosts so the Go
# binary's DNS resolver finds them instantly (avoids 10-second context
# deadline exceeded on first cold lookup via fdaa::3).
for host in bucketeer-mysql.internal \
            bucketeer-web.internal bucketeer-nginx.internal \
            bucketeer-api.internal bucketeer-httpstan.internal \
            fly-bucketeer-redis.upstash.io; do
  ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1}')
  if [ -n "$ip" ]; then
    printf '%s\t%s\n' "$ip" "$host" >> /etc/hosts
  fi
done
