#!/bin/sh
set -eu

instance_name="${1:-}"

if [ -z "$instance_name" ]; then
  echo "Usage: $0 INSTANCE" >&2
  exit 1
fi

exec limactl shell "$instance_name"
