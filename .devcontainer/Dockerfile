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

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    g++ \
    gcc \
    git \
    gnupg \
    less \
    libc6-dev \
    libffi-dev \
    libgmp-dev \
    libncurses-dev \
    libnuma-dev \
    libsqlite3-dev \
    libtinfo-dev \
    make \
    pkg-config \
    procps \
    sudo \
    tar \
    unzip \
    xz-utils \
    zlib1g-dev \
    libopenblas-dev \
    liblapack-dev \
  && rm -rf /var/lib/apt/lists/*

RUN echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
  && chmod 0440 /etc/sudoers.d/node

RUN npm install -g "pnpm@${PNPM_VERSION}"

USER node

ENV GHCUP_INSTALL_BASE_PREFIX=/home/node
ENV BOOTSTRAP_HASKELL_NONINTERACTIVE=1
ENV BOOTSTRAP_HASKELL_MINIMAL=1
ENV BOOTSTRAP_HASKELL_ADJUST_BASHRC=0
ENV PATH=/home/node/.ghcup/bin:/home/node/.cabal/bin:/home/node/.local/bin:$PATH

WORKDIR /workspaces/phd-sverlin

RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org \
  | sh

RUN ghcup --version

RUN echo "Installing GHC ${GHC_VERSION}" \
  && ghcup install ghc "${GHC_VERSION}" \
  && ghcup set ghc "${GHC_VERSION}" \
  && ghc --version \
  && rm -rf /home/node/.ghcup/tmp /home/node/.ghcup/cache

RUN echo "Installing Cabal ${CABAL_VERSION}" \
  && ghcup install cabal "${CABAL_VERSION}" \
  && ghcup set cabal "${CABAL_VERSION}" \
  && cabal --version \
  && cabal update \
  && rm -rf /home/node/.ghcup/tmp /home/node/.ghcup/cache

RUN echo "Installing HLS ${HLS_VERSION}" \
  && ghcup install hls "${HLS_VERSION}" \
  && ghcup set hls "${HLS_VERSION}" \
  && haskell-language-server-wrapper --version \
  && rm -rf /home/node/.ghcup/tmp /home/node/.ghcup/cache

RUN echo "Installing Stack ${STACK_VERSION}" \
  && ghcup install stack "${STACK_VERSION}" \
  && ghcup set stack "${STACK_VERSION}" \
  && stack --version \
  && rm -rf /home/node/.ghcup/tmp /home/node/.ghcup/cache

RUN if [[ -n "${EXTRA_CABAL_TOOLS}" ]]; then \
      cabal install ${EXTRA_CABAL_TOOLS} \
        --installdir=/home/node/.cabal/bin \
        --overwrite-policy=always; \
    fi

RUN ghc --version \
  && cabal --version \
  && stack --version \
  && haskell-language-server-wrapper --version \
  && pnpm --version
