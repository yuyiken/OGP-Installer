#!/usr/bin/env bash
# Install Open Game Panel (web panel) on a supported PHP 8.x
# github.com/sanjaysrocks
# https://github.com/SanjaySRocks/OGP-Installer/blob/master/install-panel.sh
#
# Supported: Debian 12/13, Ubuntu 22.04/24.04/26.04, Rocky/AlmaLinux/RHEL 9
#
# Options (environment variables):
#   PHP_VER=8.4      PHP branch to install (8.3, 8.4 or 8.5)
#   INSTALL_PMA=1    also install phpMyAdmin (Debian/Ubuntu only, off by default)

set -euo pipefail

PHP_VER="${PHP_VER:-8.4}"
INSTALL_PMA="${INSTALL_PMA:-0}"
WEB_ROOT=/var/www/html
CREDS_FILE=/root/ogp_panel_mysql_info
DB_NAME=ogp_panel
DB_USER=ogpuser

# First release of each branch that fixes PHP2Shell (CVE-2026-109618 / CVE-2026-109619)
declare -A PHP_MIN_PATCH=( [8.3]=8.3.36 [8.4]=8.4.27 [8.5]=8.5.12 )

cyan() {
	echo -e "\\033[36;1m${*}\033[0m"
}

die() {
	echo -e "\\033[31;1mERROR: ${*}\033[0m" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || die "Run this script as root (sudo bash $0)"
[ -n "${PHP_MIN_PATCH[$PHP_VER]:-}" ] || die "PHP_VER=$PHP_VER not supported, use one of: ${!PHP_MIN_PATCH[*]}"

. /etc/os-release
cyan "Your OS is $PRETTY_NAME"

case "$ID:$VERSION_ID" in
	debian:12|debian:13)                   FAMILY=debian ;;
	ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) FAMILY=ubuntu ;;
	rocky:9*|almalinux:9*|rhel:9*)         FAMILY=el ;;
	*) die "$PRETTY_NAME is not supported. Old releases (Debian <=11, Ubuntu <=20.04, CentOS) no longer get PHP security fixes." ;;
esac

# defs
install_debian_ubuntu(){
	export DEBIAN_FRONTEND=noninteractive
	apt-get -y update
	apt-get -y upgrade
	apt-get -y install ca-certificates curl gnupg openssl git unattended-upgrades

	if [ "$FAMILY" == "debian" ]; then
		# Sury repository: upstream PHP builds with security fixes
		curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
		dpkg -i /tmp/debsuryorg-archive-keyring.deb
		rm -f /tmp/debsuryorg-archive-keyring.deb
		echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $VERSION_CODENAME main" \
			> /etc/apt/sources.list.d/php.list
	else
		apt-get -y install software-properties-common
		add-apt-repository -y ppa:ondrej/php
	fi
	apt-get -y update

	apt-get -y install apache2 mariadb-server \
		"php$PHP_VER" "libapache2-mod-php$PHP_VER" "php$PHP_VER-cli" "php$PHP_VER-curl" "php$PHP_VER-gd" \
		"php$PHP_VER-zip" "php$PHP_VER-mbstring" "php$PHP_VER-xml" "php$PHP_VER-mysql" "php$PHP_VER-bcmath" php-pear
	update-alternatives --set php "/usr/bin/php$PHP_VER"

	if [ "$INSTALL_PMA" == "1" ]; then
		apt-get -y install phpmyadmin
	fi

	PHP_BIN="php$PHP_VER"
	WEB_USER=www-data
	PHP_INI_DIR="/etc/php/$PHP_VER/apache2/conf.d"
	MARIADB_CONF_DIR=/etc/mysql/mariadb.conf.d

	# Apply security updates (including the PHP repository) automatically
	cat > /etc/apt/apt.conf.d/52ogp-php-updates <<-'EOF'
	Unattended-Upgrade::Origins-Pattern {
		"origin=deb.sury.org";
		"origin=LP-PPA-ondrej-php";
	};
	EOF
	cat > /etc/apt/apt.conf.d/20auto-upgrades <<-'EOF'
	APT::Periodic::Update-Package-Lists "1";
	APT::Periodic::Unattended-Upgrade "1";
	EOF

	cat > /etc/apache2/conf-available/ogp-hardening.conf <<-EOF
	ServerTokens Prod
	ServerSignature Off
	TraceEnable Off
	<Directory $WEB_ROOT>
		Options -Indexes +FollowSymLinks
		AllowOverride All
		Require all granted
	</Directory>
	EOF
	a2enconf ogp-hardening
	a2dismod -f autoindex || true
}

install_el(){
	dnf -y upgrade
	dnf -y install epel-release || dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
	dnf -y install "https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
	dnf -y module reset php
	dnf -y module enable "php:remi-$PHP_VER"

	dnf -y install httpd mariadb-server git curl openssl dnf-automatic policycoreutils-python-utils \
		php php-cli php-fpm php-curl php-gd php-zip php-mbstring php-xml php-mysqlnd php-bcmath php-pear

	PHP_BIN=php
	WEB_USER=apache
	PHP_INI_DIR=/etc/php.d
	MARIADB_CONF_DIR=/etc/my.cnf.d

	# Apply updates (Remi PHP releases are not tagged as security) automatically
	sed -i 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
	systemctl enable --now dnf-automatic.timer

	cat > /etc/httpd/conf.d/ogp-hardening.conf <<-EOF
	ServerTokens Prod
	ServerSignature Off
	TraceEnable Off
	<Directory $WEB_ROOT>
		Options -Indexes +FollowSymLinks
		AllowOverride All
		Require all granted
	</Directory>
	EOF

	# SELinux: let the panel reach remote agents and write its own files
	if command -v getenforce >/dev/null && [ "$(getenforce)" != "Disabled" ]; then
		setsebool -P httpd_can_network_connect 1
		semanage fcontext -a -t httpd_sys_rw_content_t "$WEB_ROOT(/.*)?" 2>/dev/null \
			|| semanage fcontext -m -t httpd_sys_rw_content_t "$WEB_ROOT(/.*)?"
	fi

	if systemctl is-active --quiet firewalld; then
		firewall-cmd --permanent --add-service=http --add-service=https
		firewall-cmd --reload
	fi

	systemctl enable --now mariadb php-fpm httpd
}

check_php_patched(){
	local min="${PHP_MIN_PATCH[$PHP_VER]}"
	local current
	current="$("$PHP_BIN" -r 'echo PHP_VERSION;')"

	if ! "$PHP_BIN" -r "exit(version_compare(PHP_VERSION, '$min', '>=') ? 0 : 1);"; then
		if [ "$FAMILY" == "el" ]; then systemctl stop httpd; else systemctl stop apache2; fi
		die "PHP $current is vulnerable to PHP2Shell (needs >= $min). The web server has been stopped. Update PHP and run this script again."
	fi
	cyan "PHP $current installed (PHP2Shell fixed since $min)"
}

harden_php(){
	cat > "$PHP_INI_DIR/99-ogp-hardening.ini" <<-'EOF'
	expose_php = Off
	display_errors = Off
	allow_url_include = Off
	session.cookie_httponly = 1
	session.use_strict_mode = 1
	; Mitigation for CVE-2026-115560 until the next PHP release
	session.upload_progress.enabled = 0
	EOF
}

setup_database(){
	# Keep MariaDB private: the panel connects through localhost only
	cat > "$MARIADB_CONF_DIR/99-ogp.cnf" <<-'EOF'
	[mysqld]
	bind-address = 127.0.0.1
	EOF
	systemctl restart mariadb

	if [ -s "$CREDS_FILE" ]; then
		. "$CREDS_FILE"
	fi
	if [ -z "${OGPDBPass:-}" ]; then
		OGPDBPass="$(openssl rand -hex 16)"
		echo "OGPDBPass=$OGPDBPass" > "$CREDS_FILE"
	fi
	chmod 600 "$CREDS_FILE"

	# root authenticates via unix_socket, no password prompt needed.
	# Same cleanup mysql_secure_installation does: no anonymous users, no test database.
	mysql <<-EOF
	DELETE FROM mysql.global_priv WHERE User='';
	DROP DATABASE IF EXISTS test;
	CREATE DATABASE IF NOT EXISTS $DB_NAME;
	CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$OGPDBPass';
	ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$OGPDBPass';
	GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
	FLUSH PRIVILEGES;
	EOF
}

install_panel_files(){
	if [ -e "$WEB_ROOT/includes/config.inc.php" ]; then
		cyan "Panel already installed in $WEB_ROOT, leaving its files untouched"
		return
	fi

	local tmp
	tmp="$(mktemp -d)"
	git clone --depth 1 https://github.com/OpenGamePanel/OGP-Website.git "$tmp"
	echo "Status against revision:   $(git -C "$tmp" rev-parse HEAD)" > "$tmp/version.txt"
	rm -rf "$tmp/.git"

	mkdir -p "$WEB_ROOT"
	if [ -e "$WEB_ROOT/index.html" ]; then
		mv "$WEB_ROOT/index.html" "$WEB_ROOT/index_orig.html"
	fi
	cp -R "$tmp/." "$WEB_ROOT/"
	rm -rf "$tmp"

	chown -R "$WEB_USER:$WEB_USER" "$WEB_ROOT"
	find "$WEB_ROOT" -type d -exec chmod 755 {} +
	find "$WEB_ROOT" -type f -exec chmod 644 {} +

	if [ "$FAMILY" == "el" ] && command -v restorecon >/dev/null; then
		restorecon -R "$WEB_ROOT"
	fi
}

## Main

if [ "$FAMILY" == "el" ]; then
	install_el
else
	install_debian_ubuntu
fi

check_php_patched
harden_php
setup_database
install_panel_files

if [ "$FAMILY" == "el" ]; then
	systemctl restart php-fpm httpd
else
	systemctl restart apache2
fi

cyan ""
cyan "Installation completed! Use this database information in the web installer:"
echo "  MySQL Host:          localhost"
echo "  MySQL User:          $DB_USER"
echo "  MySQL User Password: $OGPDBPass"
echo "  MySQL Database Name: $DB_NAME"
echo "  (saved in $CREDS_FILE)"
cyan ""
cyan "Now browse to http://<your-server-ip>/install.php and finish the wizard RIGHT AWAY:"
cyan "until it is done, anyone who reaches that URL can configure your panel."
cyan "Once finished, delete $WEB_ROOT/install.php"
