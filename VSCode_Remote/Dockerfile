ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install a real (glibc) OpenSSH server. Because the base is Debian,
# the VS Code Server's bundled node binary runs natively — no gcompat,
# no fcntl64 errors.
#
# tar/gzip  -> VS Code Server extraction
# procps    -> `ps`, used by VS Code to detect an already-running server
# git       -> source control features inside VS Code
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
        gnupg \
        tar \
        gzip \
        procps \
        git \
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

# Claude Code CLI. Installing it here (rather than by hand inside a running
# container) means it survives add-on rebuilds, which wipe the overlay. The
# /usr/local/bin symlink puts it on PATH for non-interactive SSH sessions,
# which never source ~/.bashrc where the installer adds ~/.local/bin.
#
# The installer also seeds ~/.claude and ~/.claude.json. Those are build-time
# stubs, and run.sh would migrate them onto /data over the real credentials,
# so remove them and let run.sh link the persisted copies instead.
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
    && rm -rf /root/.claude /root/.claude.json \
    && /usr/local/bin/claude --version

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
