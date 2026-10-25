# OGP-Installer

Script supports auto install agent or panel for any os supported


1-Click Agent & Panel Installation

| OS               | Version              |   |
|------------------|----------------------|---|
| Ubuntu           | 26.04, 24.04, 22.04  | ✅ |
| Debian           | 13, 12               | ✅ |
| Rocky / Alma / RHEL | 9                 | ✅ |

Older releases (Ubuntu <= 20.04, Debian <= 11, CentOS) are no longer supported: they only ship
PHP versions that do not receive security fixes anymore.

### Security

The panel is installed with **PHP 8.4** from the maintained upstream repositories
([Sury](https://deb.sury.org/) on Debian/Ubuntu, [Remi](https://rpms.remirepo.net/) on EL9),
and the installer refuses to start the web server if PHP is older than the release that fixes
PHP2Shell (CVE-2026-109618 / CVE-2026-109619). Automatic updates are enabled so future PHP
fixes are applied without manual work.

It also keeps MariaDB listening on localhost only, disables directory listing and hides
the Apache/PHP version.

### Panel Installation

    curl -O https://raw.githubusercontent.com/SanjaySRocks/OGP-Installer/master/install-panel.sh
    sudo bash install-panel.sh

Optional: `sudo PHP_VER=8.5 bash install-panel.sh` (8.3, 8.4 or 8.5), `INSTALL_PMA=1` to also install phpMyAdmin.

### Agent Installation 
	
    curl -O https://raw.githubusercontent.com/SanjaySRocks/OGP-Installer/master/install-agent.sh
    sudo bash install-agent.sh

### OpenGamePanel GitHub
https://github.com/OpenGamePanel
