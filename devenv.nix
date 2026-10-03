{ pkgs, lib, config, ... }:
let
  flock = if pkgs.stdenv.isDarwin then pkgs.flock else pkgs.util-linux;
  vscodeExtensions = [
    "mkhl.direnv"
    "jnoortheen.nix-ide"
    "svelte.svelte-vscode"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
  ];
in
{
  dotenv.disableHint = true;

  files.".vscode/extensions.json" = {
    copyMode = "copy";
    json.recommendations = vscodeExtensions;
  };

  packages = with pkgs; [
    nodejs_24 pnpm_10
    git jq curl
    flock
    claude-code opencode
  ];

  env = {
    XDG_CACHE_HOME = "${config.devenv.root}/.cache";
    XDG_DATA_HOME = "${config.devenv.root}/.local/share";
    XDG_STATE_HOME = "${config.devenv.root}/.local/state";
  };

  services.postgres = {
    enable = true;
    package = pkgs.postgresql_17;
    listen_addresses = "127.0.0.1";
    initialDatabases = [{ name = "sverlin"; user = "sverlin"; pass = "sverlin"; }];
    # run-with-test-database.mjs creates/drops isolated databases with this role.
    initialScript = "ALTER ROLE sverlin CREATEDB;";
    hbaConf = ''
      local all all trust
      host all all 127.0.0.1/32 scram-sha-256
    '';
  };

  tasks = {
    "sverlin:setup".exec = ''
      CI=true pnpm install --frozen-lockfile
    '';

    # drizzle-kit comes from node_modules, so setup must finish first.
    "sverlin:migrate" = {
      exec = "pnpm run db:migrate";
      after = [ "sverlin:setup" ];
    };

  };

  processes.web = {
    exec = "pnpm run dev:web";
    after = [
      "devenv:processes:postgres"
      "sverlin:setup"
      "sverlin:migrate"
    ];
    restart.on = "never";
    ready.http.get = { port = 5173; path = "/api/health/ready"; };
    # Allow runtime-state.ts's 270-second cancellation budget to persist
    # terminal operation events before the local process manager exits.
    shutdown.grace = 300;
  };

  processes.postgres.ready.exec = lib.mkForce ''
    test -f "$PGDATA/.devenv_initialized" &&
      PGPASSWORD=sverlin psql -U sverlin -d sverlin -c 'SELECT 1' >/dev/null
  '';

  enterShell = ''
    # Runtime shell loading deliberately avoids dotenv.enable, which stores .env
    # contents in the Nix store. .env is trusted, local shell-compatible config.
    if [ -f "$DEVENV_ROOT/.env" ]; then
      set -a
      . "$DEVENV_ROOT/.env"
      set +a
    fi
    export DATABASE_URL="''${DATABASE_URL:-postgres://sverlin:sverlin@127.0.0.1:$PGPORT/sverlin}"
    export BETTER_AUTH_URL="''${BETTER_AUTH_URL:-http://localhost:5173}"
    export BETTER_AUTH_SECRET="''${BETTER_AUTH_SECRET:-development-only-secret-at-least-32-bytes}"
    export BETTER_AUTH_TRUSTED_ORIGINS="''${BETTER_AUTH_TRUSTED_ORIGINS:-http://localhost:5173}"
  '';
}
