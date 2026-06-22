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
        tar \
        gzip \
        procps \
        git \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
