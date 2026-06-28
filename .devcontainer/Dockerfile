FROM node:24-bookworm-slim

ARG GHC_VERSION=9.6.7
ARG CABAL_VERSION=3.14.2.0
ARG HLS_VERSION=2.14.0.0
ARG STACK_VERSION=3.7.1
ARG PNPM_VERSION=10.12.1

# Optional, e.g.:
#   "stylish-haskell"
#   "stylish-haskell fourmolu"
ARG EXTRA_CABAL_TOOLS=""

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    GHCUP_INSTALL_BASE_PREFIX=/home/node \
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    BOOTSTRAP_HASKELL_MINIMAL=1 \
    BOOTSTRAP_HASKELL_ADJUST_BASHRC=0 \
    PATH=/home/node/.ghcup/bin:/home/node/.cabal/bin:/home/node/.local/bin:$PATH

USER root

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    bash \
    bubblewrap \
    build-essential \
    ca-certificates \
    curl \
    gfortran \
    git \
    gnupg \
    less \
    libffi-dev \
    libgmp-dev \
    liblapack-dev \
    liblbfgsb-dev \
    libncurses-dev \
    libnuma-dev \
    libopenblas-dev \
    libsqlite3-dev \
    libtinfo-dev \
    pkg-config \
    procps \
    python3 \
    python3-pip \
    sudo \
    tar \
    unzip \
    xz-utils \
    zlib1g-dev; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node; \
  chmod 0440 /etc/sudoers.d/node; \
  mkdir -p /workspaces/phd-sverlin; \
  chown -R node:node /workspaces

RUN set -eux; \
  npm install -g "pnpm@${PNPM_VERSION}"

USER node

WORKDIR /workspaces/phd-sverlin

RUN set -eux; \
  curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh; \
  ghcup --version

RUN set -eux; \
  ghcup install ghc "${GHC_VERSION}"; \
  ghcup set ghc "${GHC_VERSION}"; \
  ghcup install cabal "${CABAL_VERSION}"; \
  ghcup set cabal "${CABAL_VERSION}"; \
  ghcup install hls "${HLS_VERSION}"; \
  ghcup set hls "${HLS_VERSION}"; \
  ghcup install stack "${STACK_VERSION}"; \
  ghcup set stack "${STACK_VERSION}"; \
  cabal update; \
  rm -rf /home/node/.ghcup/tmp /home/node/.ghcup/cache

RUN set -eux; \
  if [[ -n "${EXTRA_CABAL_TOOLS}" ]]; then \
    cabal install ${EXTRA_CABAL_TOOLS} \
      --installdir=/home/node/.cabal/bin \
      --overwrite-policy=always; \
  fi

RUN set -eux; \
  ghc --version; \
  cabal --version; \
  stack --version; \
  haskell-language-server-wrapper --version; \
  pnpm --version