ARG BUILD_FROM
FROM ${BUILD_FROM}
ARG BUILD_ARCH

# Install a real (glibc) OpenSSH server. Because the base is Debian,
# the VS Code Server's bundled node binary runs natively — no gcompat,
# no fcntl64 errors.
#
# tar/gzip  -> VS Code Server extraction
# procps    -> `ps`, used by VS Code to detect an already-running server
# git       -> source control features inside VS Code
#
# The rest is a working toolbox for a shell (and Claude Code) on a Home
# Assistant host:
# python3 + websockets/aiohttp/yaml -> several HA operations exist only on the
#             websocket API (dashboards, registries), and .storage must not be
#             edited on disk. From apt, not pip: bookworm's Python is
#             externally managed.
# sqlite3   -> recorder and Zigbee databases
# ping/nc/dig/ip -> network diagnosis
# yamllint, less, rsync, unzip -> everyday editing
# tzdata    -> so the TZ passed to SSH sessions resolves
#
# dist-upgrade runs first because the base image can lag months behind on
# security updates (ca-certificates, curl, xz-utils); stale CA certs break TLS.
RUN apt-get update \
    && apt-get -y dist-upgrade \
    && apt-get install -y --no-install-recommends \
        openssh-server \
        jq \
        ca-certificates \
        curl \
        tar \
        gzip \
        procps \
        git \
        python3 \
        python3-pip \
        python3-venv \
        python3-websockets \
        python3-aiohttp \
        python3-yaml \
        sqlite3 \
        iputils-ping \
        netcat-openbsd \
        dnsutils \
        iproute2 \
        yamllint \
        less \
        rsync \
        unzip \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (client only) so Claude Code can use the mounted Docker socket
# (docker_api) to inspect and exec into any container, e.g. the Scrypted add-on.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Home Assistant CLI (`ha`). It authenticates with SUPERVISOR_TOKEN, which
# run.sh passes into SSH sessions.
RUN arch="${BUILD_ARCH:-}" \
    && if [ -z "${arch}" ]; then \
         case "$(dpkg --print-architecture)" in \
           arm64) arch=aarch64 ;; \
           *)     arch=amd64 ;; \
         esac; \
       fi \
    && curl -fsSL -o /usr/local/bin/ha \
        "https://github.com/home-assistant/cli/releases/latest/download/ha_${arch}" \
    && chmod 0755 /usr/local/bin/ha \
    && /usr/local/bin/ha help > /dev/null

# Claude Code CLI. Installing it here (rather than by hand inside a running
# container) means it survives add-on rebuilds, which wipe the overlay. The
# /usr/local/bin symlink puts it on PATH for non-interactive SSH sessions,
# which never source ~/.bashrc where the installer adds ~/.local/bin.
#
# The installer also seeds ~/.claude and ~/.claude.json. Those are build-time
# stubs, and run.sh would migrate them onto /data over the real credentials,
# so remove them and let run.sh link the persisted copies instead.
#
# ~/.local/bin also goes on PATH (ENV for run.sh, .bashrc for SSH shells):
# Claude Code checks for it and warns on every `claude update` otherwise.
ENV PATH="/root/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
    && echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc \
    && rm -rf /root/.claude /root/.claude.json \
    && /usr/local/bin/claude --version

COPY deletion-guard.sh /usr/share/vscode-remote/deletion-guard.sh
COPY CLAUDE.md /usr/share/vscode-remote/CLAUDE.md
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
