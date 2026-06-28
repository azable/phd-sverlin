#!/bin/bash
set -e
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

has_output=0
for arg in "$@"; do
  case "$arg" in
    --output | -o | --output=*) has_output=1 ;;
  esac
done

if [ "$has_output" -ne 1 ]; then
  echo "compile.sh requires --output FILE. The web app now streams compiled visualizations from the backend instead of reading static/compiled.json." >&2
  exit 2
fi

cabal run -v0 compile-app --builddir=compile/dist-newstyle -- "$@"
