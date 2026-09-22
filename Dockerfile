# Docker build arguments
ARG DOTNET_VERSION=10.0
ARG JELLYFIN_WEB_VERSION=12.1

# Combined image version (Debian)
ARG OS_VERSION=trixie

# Jellyfin FFMPEG package
ARG FFMPEG_PACKAGE=jellyfin-ffmpeg8

# https://github.com/intel/compute-runtime/releases
ARG GMMLIB_VER=22.10.0
ARG IGC2_VER=2.40.13
ARG IGC2_BUILD=22418
ARG NEO_VER=26.31.39395.13
ARG IGC1_LEGACY_VER=1.0.17537.24
ARG NEO_LEGACY_VER=24.35.30872.36

#
# Build the server artifacts
#
FROM debian:${OS_VERSION}-slim AS server

ARG DOTNET_VERSION
ARG SOURCE_DIR=/src
ARG ARTIFACT_DIR=/server

ARG CONFIG=Release
ENV CONFIG=${CONFIG}

WORKDIR ${SOURCE_DIR}
COPY . .

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1

RUN apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests --yes \
    curl \
    ca-certificates \
    libicu76 \
 && curl -fsSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel ${DOTNET_VERSION} --install-dir /usr/local/bin \
 && rm -rf /var/lib/apt/lists/*

RUN dotnet publish Jellyfin.Server --arch x64 --configuration ${CONFIG} \
    --output="${ARTIFACT_DIR}" --self-contained \
    -p:DebugSymbols=false -p:DebugType=none

#
# Download pre-built web client
#
FROM debian:${OS_VERSION}-slim AS web

ARG JELLYFIN_WEB_VERSION
ARG ARTIFACT_DIR=/web

RUN apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests --yes \
    curl \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/web \
 && curl -sL "https://repo.jellyfin.org/files/server/ubuntu/latest-stable/amd64/jellyfin-web_${JELLYFIN_WEB_VERSION}+ubu2404_all.deb" -o /tmp/jellyfin-web.deb \
 && mkdir -p /tmp/jellyfin-web-extract \
 && dpkg-deb -x /tmp/jellyfin-web.deb /tmp/jellyfin-web-extract \
 && mv /tmp/jellyfin-web-extract/usr/share/jellyfin/web ${ARTIFACT_DIR} \
 && rm -rf /tmp/jellyfin-web.deb /tmp/jellyfin-web-extract /tmp/web

#
# Build the final combined image
#
FROM debian:${OS_VERSION}-slim AS combined

ARG OS_VERSION
ARG FFMPEG_PACKAGE

ARG GMMLIB_VER
ARG IGC2_VER
ARG IGC2_BUILD
ARG NEO_VER
ARG IGC1_LEGACY_VER
ARG NEO_LEGACY_VER

# Default environment variables for the Jellyfin invocation
ENV DEBIAN_FRONTEND="noninteractive" \
    LC_ALL="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    JELLYFIN_DATA_DIR="/config" \
    JELLYFIN_CACHE_DIR="/cache" \
    JELLYFIN_CONFIG_DIR="/config/config" \
    JELLYFIN_LOG_DIR="/config/log" \
    JELLYFIN_WEB_DIR="/jellyfin/jellyfin-web" \
    JELLYFIN_FFMPEG="/usr/lib/jellyfin-ffmpeg/ffmpeg"

# required for fontconfig cache
ENV XDG_CACHE_HOME=${JELLYFIN_CACHE_DIR}

# https://github.com/dlemstra/Magick.NET/issues/707
ENV MALLOC_TRIM_THRESHOLD_=131072

# Install base dependencies and Jellyfin repository
RUN apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests --yes \
    ca-certificates \
    gnupg \
    curl \
 && curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg \
 && cat <<EOF > /etc/apt/sources.list.d/jellyfin.sources
Types: deb
URIs: https://repo.jellyfin.org/master/debian
Suites: ${OS_VERSION}
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/jellyfin.gpg
EOF

# Install runtime dependencies
RUN apt-get update \
 && apt-get install --no-install-recommends --no-install-suggests --yes \
    ${FFMPEG_PACKAGE} \
    openssl \
    locales \
    libicu76 \
    libfontconfig1 \
    libfreetype6 \
    libharfbuzz0b \
    libglib2.0-0 \
    libjemalloc2 \
    libdrm2 \
    libpng16-16 \
    libjpeg62-turbo \
    zlib1g \
    libssl3 \
 && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen \
 && apt-get remove gnupg --yes \
 && apt-get clean autoclean --yes \
 && apt-get autoremove --yes \
 && rm -rf /var/cache/apt/archives* /var/lib/apt/lists/*

# Intel OpenCL Tone mapping dependencies
RUN if test "$(dpkg --print-architecture)" = "amd64"; then \
    mkdir intel-compute-runtime \
 && cd intel-compute-runtime \
 && curl -LO https://github.com/intel/compute-runtime/releases/download/${NEO_VER}/libigdgmm12_${GMMLIB_VER}_amd64.deb \
         -LO https://github.com/intel/intel-graphics-compiler/releases/download/v${IGC2_VER}/intel-igc-core-2_${IGC2_VER}+${IGC2_BUILD}_amd64.deb \
         -LO https://github.com/intel/intel-graphics-compiler/releases/download/v${IGC2_VER}/intel-igc-opencl-2_${IGC2_VER}+${IGC2_BUILD}_amd64.deb \
         -LO https://github.com/intel/compute-runtime/releases/download/${NEO_VER}/intel-opencl-icd_${NEO_VER}-0_amd64.deb \
         -LO https://github.com/intel/intel-graphics-compiler/releases/download/igc-${IGC1_LEGACY_VER}/intel-igc-core_${IGC1_LEGACY_VER}_amd64.deb \
         -LO https://github.com/intel/intel-graphics-compiler/releases/download/igc-${IGC1_LEGACY_VER}/intel-igc-opencl_${IGC1_LEGACY_VER}_amd64.deb \
         -LO https://github.com/intel/compute-runtime/releases/download/${NEO_LEGACY_VER}/intel-opencl-icd-legacy1_${NEO_LEGACY_VER}_amd64.deb \
 && apt-get install --no-install-recommends --no-install-suggests -f -y ./*.deb \
 && cd .. \
 && rm -rf intel-compute-runtime \
 ; fi \
 && apt-get clean autoclean --yes \
 && apt-get autoremove --yes \
 && rm -rf /var/cache/apt/archives* /var/lib/apt/lists/*

# Add fonts for east asian languages rendering
RUN apt-get update --yes \
 && apt-get install --no-install-recommends --no-install-suggests --yes \
        fonts-wqy-zenhei \
        fonts-wqy-microhei \
        fonts-arphic-ukai \
        fonts-arphic-uming \
        fonts-noto-cjk \
        fonts-ipafont-mincho \
        fonts-ipafont-gothic \
        fonts-unfonts-core \
 && apt-get clean autoclean --yes \
 && apt-get autoremove --yes \
 && rm -rf /var/cache/apt/archives* /var/lib/apt/lists/*

# Setup jemalloc: link the library to a path owned by us to handle arch specific library paths
RUN mkdir -p /usr/lib/jellyfin \
  && JEMALLOC_LINKED=0 \
  && if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
         if [ -f "/usr/lib/x86_64-linux-gnu/libjemalloc.so.2" ]; then \
             ln -s /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 /usr/lib/jellyfin/libjemalloc.so.2 && JEMALLOC_LINKED=1; \
         fi; \
     elif [ "$(dpkg --print-architecture)" = "arm64" ]; then \
         if [ -f "/usr/lib/aarch64-linux-gnu/libjemalloc.so.2" ]; then \
             ln -s /usr/lib/aarch64-linux-gnu/libjemalloc.so.2 /usr/lib/jellyfin/libjemalloc.so.2 && JEMALLOC_LINKED=1; \
         fi; \
     fi \
  && if [ "$JEMALLOC_LINKED" -eq 1 ]; then \
         echo "jemalloc library linked successfully." ; \
     else \
         echo "WARNING: jemalloc library .so file not found." >&2; \
     fi

# Set LD_PRELOAD to use the linked jemalloc library
ENV LD_PRELOAD=/usr/lib/jellyfin/libjemalloc.so.2

RUN mkdir -p ${JELLYFIN_DATA_DIR} ${JELLYFIN_CACHE_DIR} \
 && chmod 777 ${JELLYFIN_DATA_DIR} ${JELLYFIN_CACHE_DIR}

COPY --from=server /server /jellyfin
COPY --from=web /web /jellyfin/jellyfin-web
ARG JELLYFIN_WEB_VERSION
LABEL "org.opencontainers.image.source"="https://github.com/jellyfin/jellyfin"
LABEL "org.opencontainers.image.title"="Jellyfin"
LABEL "org.opencontainers.image.description"="The Free Software Media System"
LABEL "org.opencontainers.image.documentation"="https://jellyfin.org/docs/"
LABEL "org.opencontainers.image.version"="${JELLYFIN_WEB_VERSION}"
LABEL "org.opencontainers.image.url"="https://jellyfin.org"

EXPOSE 8096
VOLUME ${JELLYFIN_DATA_DIR} ${JELLYFIN_CACHE_DIR}
ENTRYPOINT ["/jellyfin/jellyfin"]

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 \
     CMD curl --noproxy 'localhost' -Lk -fsS "http://localhost:8096/health" || exit 1