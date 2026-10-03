#!/usr/bin/env bash
set -e

# Reload at each launch: the process manager may have inherited an older .env.
source "$(dirname "${BASH_SOURCE[0]}")/load-env.sh"

if [ "$#" -eq 0 ]; then
  builtin printf 'Usage: bash scripts/run-with-env.sh COMMAND [ARG...]\n' >&2
  exit 64
fi

# Replace the shell so signals reach the server directly, without a lock wrapper.
exec "$@"
