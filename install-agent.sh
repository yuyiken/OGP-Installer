#!/usr/bin/env bash
# Installing OGP Agent on supported debian/ubuntu/rocky/alma server
# github.com/sanjaysrocks
# https://github.com/SanjaySRocks/OGP-Installer/blob/master/install-agent.sh
#
# Supported: Debian 12/13, Ubuntu 22.04/24.04/26.04, Rocky/AlmaLinux/RHEL 9

set -euo pipefail

die() {
    echo -e "\\033[31;1mERROR: ${*}\033[0m" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || die "Run this script as root (sudo bash $0)"

. /etc/os-release

echo "Your OS is $PRETTY_NAME"

case "$ID:$VERSION_ID" in
    debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) FAMILY=debian ;;
    rocky:9*|almalinux:9*|rhel:9*) FAMILY=el ;;
    *) die "$PRETTY_NAME is not supported. Old releases (Debian <=11, Ubuntu <=20.04, CentOS) no longer get security fixes." ;;
esac

## Main

if [ "$FAMILY" == "debian" ]; then

    echo "$PRETTY_NAME Detected Updating & Installing..."
    export DEBIAN_FRONTEND=noninteractive

    # 32-bit libraries are needed by most game servers (SteamCMD)
    dpkg --add-architecture i386
    apt-get -y update
    apt-get -y upgrade

    # Installing required packages
    apt-get -y install libxml-parser-perl libpath-class-perl perl-modules screen rsync sudo e2fsprogs unzip subversion \
        libarchive-extract-perl pure-ftpd libarchive-zip-perl libhttp-daemon-perl libc6 libc6:i386 lib32gcc-s1 git curl unattended-upgrades

    # Downloading and installing agent
    tmp="$(mktemp -d)"
    curl -sSL -o "$tmp/ogp-agent-latest.deb" "https://github.com/OpenGamePanel/Easy-Installers/raw/master/Linux/Debian-Ubuntu/ogp-agent-latest.deb"
    dpkg -i "$tmp/ogp-agent-latest.deb"
    rm -rf "$tmp"

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

fi


if [ "$FAMILY" == "el" ]; then

    echo "$PRETTY_NAME Detected Installing..."

    dnf -y upgrade
    dnf -y install epel-release || dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
    dnf config-manager --set-enabled crb || subscription-manager repos --enable "codeready-builder-for-rhel-9-$(arch)-rpms"
    dnf -y install wget subversion git screen rsync sudo unzip perl-HTTP-Daemon perl-LWP-Protocol-http10 perl-ExtUtils-MakeMaker \
        perl-IO-Compress perl-Path-Class perl-XML-Parser perl-Archive-Extract proftpd proftpd-utils glibc glibc.i686 libgcc.i686 dnf-automatic

    # Downloading and installing agent
    tmp="$(mktemp -d)"
    curl -sSL -o "$tmp/ogp_agent.rpm" "https://github.com/OpenGamePanel/Easy-Installers/raw/master/Linux/CentOS/ogp_agent_rpm-1.0.0-1.noarch.rpm"
    dnf -y install "$tmp/ogp_agent.rpm"
    rm -rf "$tmp"

    sed -i 's/^upgrade_type.*/upgrade_type = security/; s/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
    systemctl enable --now dnf-automatic.timer

    if systemctl is-active --quiet firewalld; then
        # OGP agent XML-RPC port
        firewall-cmd --permanent --add-port=12679/tcp
        firewall-cmd --reload
    fi

fi

echo "Installation Completed !"
echo "Your agent credentials and encryption key are stored in /root (ogp_user_password / ogp_enc_key)."
echo "Allow port 12679/tcp ONLY from your panel's IP in your firewall."
