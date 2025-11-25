# wp-auto-deploy

Small open-source command-line tool (Bash script) to install a new WordPress site on a VPS using Nginx and MySQL. It automates:

- Creating the web root and downloading the latest WordPress
- Generating an Nginx vhost from a template
- Optionally enabling HTTPS with Let's Encrypt (Certbot)
- Creating the MySQL database/user and configuring `wp-config.php`

## Status

Version: **v0.1.0** – early version, tested on fresh Ubuntu / Debian servers with Nginx, PHP-FPM, and MySQL.

## Features

- **Menu-based flow** – run steps 1–3 in order or repeat a single step.
- **Multiple sites** – you can run the script several times for different folders/domains.
- **SSL-ready** – integrates with `certbot --nginx` for Let's Encrypt.
- **Safe defaults** – WordPress files use `www-data` owner and restrictive permissions.

## Supported environment

Recommended:

- Debian or Ubuntu server
- Nginx installed and using `/etc/nginx/sites-available` and `/etc/nginx/sites-enabled`
- PHP-FPM installed (e.g. `php8.x-fpm`)
- MySQL or MariaDB server with root access available without password when run as `root`
- `wget`, `unzip`, and (optional) `certbot` installed

The script will:

- Warn you if the OS is not Debian/Ubuntu.
- Check that `wget`, `unzip`, `nginx`, and `mysql` are available.
- Use the bundled Nginx template at `templates/nginx-wordpress.conf`.

If your distribution uses a different HTTP user (e.g. `nginx` instead of `www-data`) or a different PHP-FPM socket path, you may need to adjust those manually.

## Project structure

- `wp-auto-deploy.sh` – main interactive script.
- `templates/nginx-wordpress.conf` – default Nginx vhost template with placeholders.

Clone this repo to any folder on your server, for example `/opt/wp-auto-deploy`, and run the script from there.

## Installation

On a fresh Ubuntu/Debian server, you have two options:

- **Option A (simple, recommended):** just run the script and let it check/install the required packages for you when needed.
- **Option B (manual):** install all dependencies yourself up front with `apt`:

```bash
sudo apt update
sudo apt install nginx mysql-server php-fpm php-mysql wget unzip
# Optional, for SSL via Let's Encrypt:
sudo apt install certbot python3-certbot-nginx
```

Then clone this project:

```bash
cd /opt
sudo git clone https://github.com/Sliim-Bouzidi/wp-auto-deploy.git
cd wp-auto-deploy
sudo chmod +x wp-auto-deploy.sh
```

## Usage

Run the script as root:

```bash
sudo ./wp-auto-deploy.sh
```

You will see a menu:

1. Setup WordPress files  
2. Setup Nginx (HTTP)  
3. Setup SSL (HTTPS with Certbot)  
4. Setup database and `wp-config.php`  
5. Exit  

### Step 1 – WordPress files

- Enter a folder name, for example `myblog`.
- The script will create `/var/www/myblog`, download the latest WordPress zip, unpack it there, and set file permissions.

You can repeat step 1 for different folder names to host multiple sites on the same server.

### Step 2 – Nginx (HTTP only)

- Enter the domain, e.g. `example.com`.
- Enter the folder name where you installed WordPress (e.g. `myblog` → `/var/www/myblog`).
- The script:
  - Copies `templates/nginx-wordpress.conf` to `/etc/nginx/sites-available/<domain>.conf`.
  - Replaces placeholders with your domain, web root and detected PHP-FPM socket.
  - Creates a symlink in `/etc/nginx/sites-enabled`.
  - Runs `nginx -t` and reloads Nginx if the config is valid.

If automatic PHP-FPM socket detection fails, the script will use `/run/php/php-fpm.sock`. Edit the generated config to match your environment if Nginx complains.

### Step 3 – SSL (HTTPS with Certbot)

- Enter the same domain you used for step 2.
- The script:
  - Checks that an Nginx config exists for that domain.
  - Optionally installs `certbot` and `python3-certbot-nginx` with `apt` on Debian/Ubuntu if they are missing.
  - Runs `certbot --nginx -d <domain> -d www.<domain>` to obtain and configure a free Let's Encrypt certificate.

Make sure your domain’s DNS `A` record points to your server’s public IP *before* running this step.

### Step 4 – Database + wp-config.php

- Enter:
  - MySQL database name
  - MySQL username
  - MySQL password
  - WordPress folder name
- The script:
  - Creates the database if it does not exist.
  - Creates the MySQL user if it does not exist.
  - Grants the user full privileges on that database.
  - Copies `wp-config-sample.php` to `wp-config.php` if needed.
  - Injects your DB credentials into `wp-config.php`.
  - Ensures the web root is owned by `www-data`.

This assumes that running `mysql` as `root` does not require a password (the default on many fresh Ubuntu/Debian installs). If your MySQL root user requires a password, you will need to adapt the script to pass credentials or use a different administrative user.

## Will this work on other VPS providers?

Yes, as long as:

- The server runs a Debian/Ubuntu-like system.
- You install the required packages listed above.
- Nginx uses the standard Debian layout (`/etc/nginx/sites-available` + `sites-enabled`).
- PHP-FPM is installed and exposes a socket in `/run/php`.
- MySQL root access works from the shell.

This means it should work on Hetzner, DigitalOcean, AWS, etc. if you start from an Ubuntu/Debian image and install the prerequisites.

On other distributions (CentOS, AlmaLinux, Arch, etc.) you may need to:

- Change the service user (`www-data` → `nginx` or something else).
- Change Nginx paths and include directives.
- Adjust the PHP-FPM socket path.

## Nginx template

The bundled `templates/nginx-wordpress.conf` is a generic WordPress server block that:

- Listens on port 80 (HTTP only; HTTPS is added later by Certbot).
- Uses `try_files` so pretty permalinks work.
- Forwards `.php` files to PHP-FPM via a Unix socket.
- Blocks access to hidden files and logs.

The script replaces three placeholders:

- `__SERVER_NAME__` → your domain and `www.` subdomain.
- `__WEBROOT__` → `/var/www/<folder>`.
- `__PHP_FPM_SOCK__` → detected PHP-FPM socket path (or `/run/php/php-fpm.sock` fallback).

You can customize this template if you want to tweak caching, logging, or advanced Nginx options.

## Security notes

- Choose strong MySQL passwords.
- Keep your system updated (`apt upgrade`).
- Limit SSH access and consider a firewall (UFW) and fail2ban.
- Remove any test sites or databases you do not use.

## Contributing

Issues and pull requests are welcome.

Before contributing, please:

- Open an issue to discuss big changes.
- Keep the script POSIX/Bash and easy to read.
