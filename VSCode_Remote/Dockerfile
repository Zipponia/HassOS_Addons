ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install a real (glibc) OpenSSH server. Because the base is Debian,
# the VS Code Server's bundled node binary runs natively — no gcompat,
# no fcntl64 errors.
#
# tar/gzip  -> VS Code Server extraction
# procps    -> `ps`, used by VS Code to detect an already-running server
# git       -> source control features inside VS Code
RUN apt-get update \
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

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
