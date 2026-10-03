# Shared by devenv shells and server launches. .env is trusted local shell config.
sverlin_load_env() {
  local repository_root
  repository_root="$(dirname "${BASH_SOURCE[0]}")/.."
  if [ -f "$repository_root/.env" ]; then
    set -a
    source "$repository_root/.env"
    local result=$?
    set +a
    if [ "$result" -ne 0 ]; then return "$result"; fi
  fi

  # Development defaults belong only to the Dev Container, not production.
  if [ -n "${DEVENV_ROOT:-}" ]; then
    export DATABASE_URL="${DATABASE_URL:-postgres://sverlin:sverlin@127.0.0.1:${PGPORT:-5432}/sverlin}"
    export BETTER_AUTH_URL="${BETTER_AUTH_URL:-http://localhost:5173}"
    export BETTER_AUTH_SECRET="${BETTER_AUTH_SECRET:-development-only-secret-at-least-32-bytes}"
    export BETTER_AUTH_TRUSTED_ORIGINS="${BETTER_AUTH_TRUSTED_ORIGINS:-http://localhost:5173}"
  fi
}

sverlin_load_env
