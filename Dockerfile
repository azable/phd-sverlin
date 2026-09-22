# syntax=docker/dockerfile:1.7

FROM node:24.19.0-bookworm-slim AS node-toolchain

FROM haskell:9.10.3-bookworm AS toolchain

ARG HIGHS_VERSION=1.15.1

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=node-toolchain /usr/local/ /usr/local/

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bubblewrap \
        ca-certificates \
        cmake \
        curl \
        gfortran \
        git \
        jq \
        libfreetype6-dev \
        libharfbuzz-dev \
        liblapack-dev \
        liblbfgsb-dev \
        libopenblas-dev \
        openssh-client \
        pkg-config \
        util-linux \
        xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global pnpm@10.12.1

# MIP invokes the HiGHS executable. Build the same pinned release for amd64 and arm64.
RUN curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --retry-all-errors \
        "https://github.com/ERGO-Code/HiGHS/archive/refs/tags/v${HIGHS_VERSION}.tar.gz" \
        -o /tmp/highs.tar.gz \
    && echo "a840d269dff2fafb371dd247df13ad5e026d7ce3b35ad3dc1eedd59bf0c2fb16  /tmp/highs.tar.gz" \
        | sha256sum -c - \
    && tar -xzf /tmp/highs.tar.gz -C /tmp \
    && cmake \
        -S "/tmp/HiGHS-${HIGHS_VERSION}" \
        -B /tmp/highs-build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
    && cmake --build /tmp/highs-build --parallel 2 --target highs-bin \
    && install -m 0755 /tmp/highs-build/bin/highs /usr/local/bin/highs \
    && rm -rf /tmp/highs.tar.gz /tmp/highs-build "/tmp/HiGHS-${HIGHS_VERSION}"

RUN node --version \
    && pnpm --version \
    && ghc --version \
    && stack --version \
    && highs --version \
    && flock --version

# Resolve external compiler dependencies before copying project-owned source.
FROM toolchain AS compiler-dependencies

WORKDIR /workspaces/phd-sverlin/compile

ENV STACK_ROOT=/opt/sverlin-stack-seed

COPY compile/stack.yaml compile/stack.yaml.lock compile/compile.cabal ./
COPY compile/vendor/MIP-0.2.0.1/MIP.cabal ./vendor/MIP-0.2.0.1/MIP.cabal

RUN stack build --jobs=1 --only-dependencies

FROM compiler-dependencies AS build

WORKDIR /workspaces/phd-sverlin

ENV STACK_ROOT=/opt/sverlin-stack-seed \
    XDG_CACHE_HOME=/workspaces/phd-sverlin/.cache \
    XDG_STATE_HOME=/workspaces/phd-sverlin/.local/state

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN mkdir -p outputs \
    && pnpm run build

RUN prepared_binary="$(node -e "const fs=require('fs'); process.stdout.write(JSON.parse(fs.readFileSync('.cache/sverlin/compiler.json','utf8')).binaryPath)")" \
    && prepared_environment="$(node -e "const fs=require('fs'); process.stdout.write(JSON.parse(fs.readFileSync('.cache/sverlin/compiler.json','utf8')).ghcEnvironmentPath)")" \
    && install -m 0755 "${prepared_binary}" /tmp/sverlin-compile \
    && install -m 0644 "${prepared_environment}" /tmp/sverlin-ghc.environment \
    && node -e "const fs=require('fs'); const descriptor=JSON.parse(fs.readFileSync('.cache/sverlin/compiler.json','utf8')); descriptor.binaryPath='/usr/local/bin/sverlin-compile'; descriptor.ghcEnvironmentPath='/workspaces/phd-sverlin/.cache/sverlin/ghc.environment'; fs.writeFileSync('/tmp/sverlin-compiler.json', JSON.stringify(descriptor, null, 2) + '\\n')"

FROM build AS verification

RUN pnpm run check \
    && pnpm run lint \
    && pnpm run test:unit \
    && pnpm run test:compiler \
    && pnpm run test:examples

FROM toolchain AS production-dependencies

WORKDIR /workspaces/phd-sverlin

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
RUN pnpm install --prod --frozen-lockfile --ignore-scripts

# Generated Sverlin source is interpreted at request time, so the runtime needs
# GHC and its package store. The official slim variant omits profiling libraries
# and common build utilities while retaining the interpreter toolchain.
FROM haskell:9.10.3-slim-bookworm AS runtime

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=node-toolchain /usr/local/ /usr/local/
COPY --from=toolchain /usr/local/bin/highs /usr/local/bin/highs

RUN apt-get update \
    && apt-get purge -y git git-man \
    && apt-get install -y --no-install-recommends \
        bubblewrap \
        ca-certificates \
        libfreetype6-dev \
        libharfbuzz-dev \
        liblapack-dev \
        liblbfgsb-dev \
        libopenblas-dev \
        libstdc++6 \
        util-linux \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/local/bin/cabal /usr/local/bin/stack /usr/local/bin/plan.json \
    && node --version \
    && ghc --version \
    && highs --version \
    && flock --version

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    BODY_SIZE_LIMIT=20M \
    SHUTDOWN_TIMEOUT=300 \
    PROTOCOL_HEADER=x-forwarded-proto \
    HOST_HEADER=x-forwarded-host \
    SVERLIN_SHUTDOWN_TIMEOUT_SECONDS=270 \
    SVERLIN_SCRATCH_DIR=/tmp/sverlin

WORKDIR /workspaces/phd-sverlin

RUN useradd --create-home --uid 10001 sverlin \
    && mkdir -p /tmp/sverlin outputs .cache .local/state \
    && chown -R sverlin:sverlin /tmp/sverlin outputs .cache .local

COPY --from=production-dependencies --chown=sverlin:sverlin /workspaces/phd-sverlin/node_modules ./node_modules
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/build ./build
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/build-migrate ./build-migrate
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/examples ./examples
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/drizzle ./drizzle
COPY --from=build /tmp/sverlin-compile /usr/local/bin/sverlin-compile
COPY --from=build --chown=sverlin:sverlin /tmp/sverlin-compiler.json ./.cache/sverlin/compiler.json
COPY --from=build --chown=sverlin:sverlin /tmp/sverlin-ghc.environment ./.cache/sverlin/ghc.environment
COPY --from=build --chown=sverlin:sverlin /opt/sverlin-stack-seed/snapshots /opt/sverlin-stack-seed/snapshots
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/compile/.stack-work/install ./compile/.stack-work/install
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/compile/stack.yaml /workspaces/phd-sverlin/compile/stack.yaml.lock /workspaces/phd-sverlin/compile/compile.cabal ./compile/
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/compile/app ./compile/app
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/compile/cbits ./compile/cbits
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/compile/fonts ./compile/fonts
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/compile/src ./compile/src
COPY --from=build --chown=sverlin:sverlin /workspaces/phd-sverlin/compile/vendor ./compile/vendor
COPY --chown=sverlin:sverlin package.json ./package.json

USER sverlin

EXPOSE 3000

CMD ["node", "build"]
