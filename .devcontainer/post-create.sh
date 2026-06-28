#!/usr/bin/env bash
set -euo pipefail

repo_root="/workspaces/phd-sverlin"

sudo mkdir -p "${repo_root}/.pnpm-store" "${repo_root}/node_modules"
sudo chown -R node:node "${repo_root}/.pnpm-store" "${repo_root}/node_modules"

pnpm config set store-dir "${repo_root}/.pnpm-store"
pnpm install --frozen-lockfile

mkdir -p "${repo_root}/outputs"
cabal build -v0 compile-app --builddir=compile/dist-newstyle

sudo npm install -g @openai/codex

for tool in hlint hindent stylish-haskell; do
  command -v "${tool}"
done
