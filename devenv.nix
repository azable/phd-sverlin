{ pkgs, lib, config, ... }:
let
  # Match compile/stack.yaml and the production Dockerfile's GHC ABI.
  ghc = pkgs.haskell.compiler.ghc9103;
  # Match the production solver, including its archive checksum (Dockerfile).
  highs = pkgs.highs.overrideAttrs (_: {
    version = "1.15.1";
    src = pkgs.fetchurl {
      url = "https://github.com/ERGO-Code/HiGHS/archive/refs/tags/v1.15.1.tar.gz";
      sha256 = "a840d269dff2fafb371dd247df13ad5e026d7ce3b35ad3dc1eedd59bf0c2fb16";
    };
  });
  flock = if pkgs.stdenv.isDarwin then pkgs.flock else pkgs.util-linux;
  vscodeExtensions = [
    "mkhl.direnv"
    "jnoortheen.nix-ide"
    "svelte.svelte-vscode"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "haskell.haskell"
    "0xCD.stylish-hindent"
  ];
in
{
  dotenv.disableHint = true;

  files.".vscode/extensions.json" = {
    copyMode = "copy";
    json.recommendations = vscodeExtensions;
  };

  languages.haskell = {
    enable = true;
    package = ghc;
    # Match prepare-compiler.mjs's single-job build to bound compiler memory.
    stack.args = [ "--no-nix" "--system-ghc" "--no-install-ghc" "--jobs=1" ];
  };

  packages = with pkgs; [
    nodejs_24 pnpm_10
    haskellPackages.hindent haskellPackages.hlint haskellPackages.stylish-haskell
    pkg-config clang gfortran cmake gnumake
    # openblasCompat, not openblas: nixpkgs builds openblas with USE64BITINT
    # (ILP64) while exporting unsuffixed symbols, so hmatrix's 32-bit CInt
    # arguments are read as 64-bit and LAPACK rejects LDC/LWORK. It also
    # supplies libblas/liblapack/libcblas, replacing the separate lapack.
    openblasCompat harfbuzz freetype glib libsysprof-capture pcre2 libffi zlib
    git jq curl
    highs flock
    claude-code opencode
  ];

  env = {
    STACK_ROOT = "${config.devenv.root}/.cache/stack";
    XDG_CACHE_HOME = "${config.devenv.root}/.cache";
    XDG_DATA_HOME = "${config.devenv.root}/.local/share";
    XDG_STATE_HOME = "${config.devenv.root}/.local/state";
    SVERLIN_SCRATCH_DIR = "${config.devenv.root}/tmp/sverlin";
    # Same allowance as the previous development environment: cold compilation
    # can take longer than the production request path's prepared compiler.
    SVERLIN_COMPILE_TIMEOUT_MS = "300000";
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

    # Deliberately unconditional. devenv forbids status with execIfModified,
    # and neither alone is correct here: execIfModified would skip after a
    # .cache/ wipe and leave no descriptor, while status would skip whenever
    # a descriptor exists and never pick up changed compiler sources.
    # prepare-compiler.mjs already owns freshness via its source fingerprint,
    # and an up-to-date stack build is a cheap no-op.
    "sverlin:compiler" = {
      exec = "pnpm run prepare:compiler";
      after = [ "sverlin:setup" ];
    };
  };

  processes.web = {
    exec = "pnpm run dev:web";
    after = [
      "devenv:processes:postgres"
      "sverlin:setup"
      "sverlin:migrate"
      "sverlin:compiler"
    ];
    restart.on = "never";
    ready.http.get = { port = 5173; path = "/api/health/ready"; };
    # Match Dockerfile's shutdown ceiling so runtime-state.ts's 270-second
    # cancellation budget has time to persist terminal operation events.
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
