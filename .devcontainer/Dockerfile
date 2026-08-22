# syntax=docker/dockerfile:1.7

FROM haskell:9.10.3-bookworm

ARG TARGETARCH
ARG GHC_VERSION=9.10.3
ARG HLS_VERSION=2.14.0.0
ARG HIGHS_VERSION=1.15.1

ENV DEBIAN_FRONTEND=noninteractive

# Native dependencies for numeric-optimization / hmatrix / L-BFGS-B,
# bubblewrap for sandboxing, and OpenSSH client support for forwarded
# host SSH agents (including YubiKey-backed Git authentication).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bubblewrap \
        ca-certificates \
        cmake \
        curl \
        gfortran \
        git \
        liblapack-dev \
        liblbfgsb-dev \
        libopenblas-dev \
        openssh-client \
        pkg-config \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# The MIP package uses the HiGHS command-line executable as its backend. Build
# one pinned, architecture-independent release rather than relying on a distro
# package whose availability differs between amd64 and arm64.
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

# Install HLS matching GHC 9.10.3.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) \
            hls_platform="x86_64-linux-deb12"; \
            hls_sha256="b12e11da456637293db56e32fce8b6265b5a2c4bfa643a2bdc50c7c49260d5e2"; \
            ;; \
        arm64) \
            hls_platform="aarch64-linux-ubuntu2204"; \
            hls_sha256="7d2e9356487a802a2ccf903f570872c028fb91b1d34906629c3a0054a1f33daa"; \
            ;; \
        *) \
            echo "Unsupported architecture: ${TARGETARCH}"; \
            exit 1; \
            ;; \
    esac; \
    hls_archive="haskell-language-server-${HLS_VERSION}-${hls_platform}.tar.xz"; \
    hls_url="https://github.com/haskell/haskell-language-server/releases/download/${HLS_VERSION}/${hls_archive}"; \
    curl \
        --fail \
        --location \
        --retry 5 \
        --retry-delay 2 \
        --retry-all-errors \
        "${hls_url}" \
        -o /tmp/hls.tar.xz; \
    echo "${hls_sha256}  /tmp/hls.tar.xz" | sha256sum -c -; \
    mkdir -p /tmp/hls; \
    tar -xJf /tmp/hls.tar.xz -C /tmp/hls; \
    wrapper="$(find /tmp/hls -type f -name 'haskell-language-server-wrapper' -print -quit)"; \
    server="$(find /tmp/hls -type f -name "haskell-language-server-${GHC_VERSION}" -print -quit)"; \
    test -n "${wrapper}"; \
    test -n "${server}"; \
    install -m 0755 "${wrapper}" \
        /usr/local/bin/haskell-language-server-wrapper; \
    install -m 0755 "${server}" \
        "/usr/local/bin/haskell-language-server-${GHC_VERSION}"; \
    ln -sf \
        "haskell-language-server-${GHC_VERSION}" \
        /usr/local/bin/haskell-language-server; \
    rm -rf /tmp/hls /tmp/hls.tar.xz

# Verify Haskell environment during image construction.
RUN ghc --version \
    && cabal --version \
    && highs --version \
    && haskell-language-server-wrapper --version
