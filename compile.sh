#!/bin/bash
set -e
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

has_output=0
for arg in "$@"; do
  case "$arg" in
    --output | -o | --output=*) has_output=1 ;;
  esac
done

if [ "$has_output" -eq 1 ]; then
  cabal run -v0 compile-app --builddir=compile/dist-newstyle -- "$@"
else
  cabal run -v0 compile-app --builddir=compile/dist-newstyle -- --output static/compiled.json "$@"
fi
