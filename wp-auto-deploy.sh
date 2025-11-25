#!/bin/bash

VERSION="0.1.0"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g. sudo $0)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_TEMPLATE="$SCRIPT_DIR/templates/nginx-wordpress.conf"

if [ ! -f "$NGINX_TEMPLATE" ]; then
  echo "Nginx template not found at $NGINX_TEMPLATE"
  exit 1
fi

if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID=${ID:-unknown}
  OS_LIKE=${ID_LIKE:-}
  if [ "$OS_ID" != "debian" ] && [ "$OS_ID" != "ubuntu" ] && [[ "$OS_LIKE" != *"debian"* ]] && [[ "$OS_LIKE" != *"ubuntu"* ]]; then
    echo "Warning: this script was tested on Debian/Ubuntu. Continue anyway? [y/N]"
    read -r CONTINUE_ANYWAY
    case "$CONTINUE_ANYWAY" in
      y|Y) ;;
      *) echo "Aborting."; exit 1 ;;
    esac
  fi
fi

REQUIRED_CMDS=("wget" "unzip" "nginx" "mysql")
MISSING=()
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING+=("$cmd")
  fi
done

if [ "${#MISSING[@]}" -ne 0 ]; then
  echo "Missing required commands: ${MISSING[*]}"

  if [ "$OS_ID" = "debian" ] || [ "$OS_ID" = "ubuntu" ] || [[ "$OS_LIKE" == *"debian"* ]] || [[ "$OS_LIKE" == *"ubuntu"* ]]; then
    echo "Some required packages are missing."
    read -rp "Do you want to install them now with apt? (y/n): " INSTALL_DEPS

    if [[ "$INSTALL_DEPS" == "y" || "$INSTALL_DEPS" == "Y" ]]; then
      apt update
      apt install -y nginx mysql-server php-fpm php-mysql wget unzip

      # Re-check commands after installation
      MISSING=()
      for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
          MISSING+=("$cmd")
        fi
      done

      if [ "${#MISSING[@]}" -ne 0 ]; then
        echo "The following commands are still missing after apt installation: ${MISSING[*]}"
        echo "Please install them manually and run this script again."
        exit 1
      fi
    else
      echo "Please install the missing commands manually, for example on Ubuntu:"
      echo "  apt update && apt install nginx mysql-server php-fpm php-mysql wget unzip"
      exit 1
    fi
  else
    echo "Automatic package installation is only supported on Debian/Ubuntu."
    echo "Please install the missing commands using your distribution's package manager."
    exit 1
  fi
fi

echo "=== WordPress Setup Menu (wp-auto-deploy v$VERSION) ==="

while true; do
  echo ""
  echo "Select a step to perform (recommended order: 1 → 2 → 3 → 4):"
  echo "1) Setup WordPress files"
  echo "2) Setup Nginx (HTTP)"
  echo "3) Setup SSL (HTTPS with Certbot)"
  echo "4) Setup database and wp-config.php"
  echo "5) Exit"

  read -rp "Enter your choice [1-5]: " CHOICE

  case "$CHOICE" in
    1)
      read -rp "Enter folder name for the site (e.g., mysite): " FOLDER
      if [ -z "$FOLDER" ]; then
        echo "Folder name cannot be empty."
        continue
      fi

      WEBROOT="/var/www/$FOLDER"
      echo "Creating folder at $WEBROOT and downloading WordPress..."
      mkdir -p "$WEBROOT"
      cd /tmp || exit 1
      wget -q https://wordpress.org/latest.zip
      unzip -q latest.zip
      cp -r wordpress/* "$WEBROOT"
      rm -rf wordpress latest.zip

      chown -R www-data:www-data "$WEBROOT"
      find "$WEBROOT" -type d -exec chmod 755 {} \;
      find "$WEBROOT" -type f -exec chmod 644 {} \;

      echo "WordPress downloaded to $WEBROOT."
      ;;
    2)
      read -rp "Enter domain name (e.g., example.com): " DOMAIN
      if [ -z "$DOMAIN" ]; then
        echo "Domain cannot be empty."
        continue
      fi

      read -rp "Enter folder name where WordPress is installed: " FOLDER
      if [ -z "$FOLDER" ]; then
        echo "Folder name cannot be empty."
        continue
      fi

      WEBROOT="/var/www/$FOLDER"
      if [ ! -d "$WEBROOT" ]; then
        echo "Folder $WEBROOT does not exist. Run step 1 first or check the folder name."
        continue
      fi

      PHP_FPM_SOCK=$(find /run/php -maxdepth 1 -type s -name "php*-fpm.sock" 2>/dev/null | head -n 1)
      if [ -z "$PHP_FPM_SOCK" ]; then
        echo "Could not automatically detect PHP-FPM socket in /run/php."
        echo "A default value /run/php/php-fpm.sock will be used; adjust fastcgi_pass manually if needed."
        PHP_FPM_SOCK="/run/php/php-fpm.sock"
      fi

      NGINX_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
      echo "Creating Nginx config at $NGINX_CONF..."

      cp "$NGINX_TEMPLATE" "$NGINX_CONF"
      sed -i "s|__SERVER_NAME__|$DOMAIN www.$DOMAIN|g" "$NGINX_CONF"
      sed -i "s|__WEBROOT__|$WEBROOT|g" "$NGINX_CONF"
      sed -i "s|__PHP_FPM_SOCK__|$PHP_FPM_SOCK|g" "$NGINX_CONF"

      if [ ! -e "/etc/nginx/sites-enabled/$DOMAIN.conf" ]; then
        ln -s "$NGINX_CONF" "/etc/nginx/sites-enabled/$DOMAIN.conf"
      fi

      if nginx -t; then
        systemctl reload nginx
        echo "Nginx config created and reloaded."
      else
        echo "Nginx configuration test failed. Please fix the errors above and run nginx -t again."
        continue
      fi

      echo "Nginx HTTP virtual host created. Run step 3 to enable HTTPS with Let's Encrypt."
      ;;
    3)
      read -rp "Enter domain name for SSL (e.g., example.com): " DOMAIN
      if [ -z "$DOMAIN" ]; then
        echo "Domain cannot be empty."
        continue
      fi

      NGINX_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
      if [ ! -f "$NGINX_CONF" ]; then
        echo "Nginx config $NGINX_CONF not found. Run 'Setup Nginx (HTTP)' first."
        continue
      fi

      echo "Make sure DNS for $DOMAIN points to this server's IP before enabling SSL."

      if ! command -v certbot >/dev/null 2>&1; then
        echo "certbot is not installed."
        if [ "$OS_ID" = "debian" ] || [ "$OS_ID" = "ubuntu" ] || [[ "$OS_LIKE" == *"debian"* ]] || [[ "$OS_LIKE" == *"ubuntu"* ]]; then
          read -rp "Install certbot and python3-certbot-nginx now with apt? (y/n): " INSTALL_CERTBOT
          if [[ "$INSTALL_CERTBOT" == "y" || "$INSTALL_CERTBOT" == "Y" ]]; then
            apt update
            apt install -y certbot python3-certbot-nginx
          else
            echo "Please install certbot manually, for example:"
            echo "  apt install certbot python3-certbot-nginx"
            continue
          fi
        else
          echo "Automatic certbot installation is only supported on Debian/Ubuntu."
          echo "Please install certbot using your distribution's package manager."
          continue
        fi
      fi

      if ! command -v certbot >/dev/null 2>&1; then
        echo "certbot is still not available. Cannot configure SSL."
        continue
      fi

      certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN"
      echo "SSL enabled (if Certbot completed successfully)."
      ;;
    4)
      read -rp "Enter MySQL database name: " DB_NAME
      read -rp "Enter MySQL username: " DB_USER
      read -rsp "Enter MySQL password: " DB_PASS
      echo ""
      read -rp "Enter WordPress folder (e.g., mysite): " FOLDER

      if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$FOLDER" ]; then
        echo "Database, user, password, and folder are all required."
        continue
      fi

      WEBROOT="/var/www/$FOLDER"
      if [ ! -d "$WEBROOT" ]; then
        echo "Folder $WEBROOT does not exist. Run step 1 first or check the folder name."
        continue
      fi

      echo "Creating database and user..."
      mysql <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

      if [ ! -f "$WEBROOT/wp-config.php" ]; then
        cp "$WEBROOT/wp-config-sample.php" "$WEBROOT/wp-config.php"
      fi

      sed -i "s/database_name_here/$DB_NAME/" "$WEBROOT/wp-config.php"
      sed -i "s/username_here/$DB_USER/" "$WEBROOT/wp-config.php"
      sed -i "s/password_here/$DB_PASS/" "$WEBROOT/wp-config.php"

      chown -R www-data:www-data "$WEBROOT"

      echo "Database configured and wp-config.php updated."
      ;;
    5)
      echo "Exiting..."
      exit 0
      ;;
    *)
      echo "Invalid choice. Please enter 1-5."
      ;;
  esac

done
