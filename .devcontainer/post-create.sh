#!/usr/bin/env bash
set -euo pipefail

repo_root="/workspaces/phd-sverlin"

sudo mkdir -p "${repo_root}/.pnpm-store" "${repo_root}/node_modules"
sudo chown -R node:node "${repo_root}/.pnpm-store" "${repo_root}/node_modules"

pnpm config set store-dir "${repo_root}/.pnpm-store"
pnpm install --frozen-lockfile

warmup_output="${TMPDIR:-/tmp}/sverlin-post-create-compiled.json"
pnpm run compile -- --output "${warmup_output}" --json --seed 1
rm -f "${warmup_output}"

sudo npm install -g @openai/codex

for tool in hlint hindent stylish-haskell; do
  command -v "${tool}"
done
