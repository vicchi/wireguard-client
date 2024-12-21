ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION}

ARG VERSION
ARG UBUNTU_VERSION

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN <<EOT
apt-get update -qy
apt-get install -qy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    curl \
    debconf-utils \
    iptables \
    software-properties-common
echo resolvconf resolvconf/linkify-resolvconf boolean false | debconf-set-selections
apt-get install -qy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    iproute2 \
    resolvconf \
    wireguard \
    wireguard-tools
apt-get clean
rm -rf /var/lib/apt/lists/*
ln -fs /usr/share/zoneinfo/Europe/London /etc/localtime
EOT

# COPY wgnet0.conf /etc/wireguard/.
COPY ./docker/wireguard-client/files/vpn-startup.sh /.

LABEL org.opencontainers.image.url="https://github.com/vicchi/wireguard-client"
LABEL org.opencontainers.image.documentation="https://github.com/vicchi/wireguard-client/blob/master/README.md"
LABEL org.opencontainers.image.source="https://github.com/vicchi/wireguard-client"
LABEL org.opencontainers.image.version=${VERSION}
LABEL org.opencontainers.image.revision=${VERSION}
LABEL org.opencontainers.image.vendor="Gary Gale"
LABEL org.opencontainers.image.licenses="BSD-3-Clause"
LABEL org.opencontainers.image.description="Wireguard VPN Client"
LABEL org.opencontainers.image.title="Wireguard VPN Client"
LABEL org.opencontainers.image.base.name=docker.io/ubuntu:${UBUNTU_VERSION}

EXPOSE 9696

ENTRYPOINT ["/vpn-startup.sh"]
STOPSIGNAL SIGINT