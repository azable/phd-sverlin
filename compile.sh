#!/bin/bash
cabal run -v0 compile-app --builddir=compile/dist-newstyle -- "$@"
