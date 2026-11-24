#!/bin/sh
set -eu
ZB_LAUNCH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$ZB_LAUNCH_DIR/bootstrap/bootstrap.sh" --project-root "$ZB_LAUNCH_DIR" --mode server --action reset "$@"
