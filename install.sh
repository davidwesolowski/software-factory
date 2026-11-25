#!/usr/bin/env bash
# Forwarder: copies of /install-factory older than the claude-code/ move run this path.
exec bash "$(dirname "$0")/claude-code/install.sh" "$@"
