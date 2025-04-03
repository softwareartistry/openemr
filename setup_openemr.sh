#!/bin/bash
set -e

echo "======== OpenEMR Setup Script ========"
echo "This script will clone OpenEMR, create necessary files, and build a custom Docker image."

# Step 1: Clone the repository
echo -e "\n\n==== CLONING REPOSITORY ===="
if [ -d "openemr" ]; then
  echo "Directory 'openemr' already exists. Do you want to remove it and clone again? (y/n)"
  read -r answer
  if [ "$answer" = "y" ]; then
    rm -rf openemr
    git clone git@github.com:softwareartistry/openemr.git
  fi
else
  git clone git@github.com:softwareartistry/openemr.git
fi

# Step 2: Enter the directory
echo -e "\n\n==== ENTERING DIRECTORY ===="
cd openemr
echo "Now in directory: $(pwd)"

# Step 3: Create necessary files
echo -e "\n\n==== CREATING CONFIGURATION FILES ===="

# Create Dockerfile.simple
echo "Creating Dockerfile.simple..."
cat > Dockerfile.simple << 'EOF'
# Use official PHP-FPM image
FROM php:8.1-fpm

# Install required PHP extensions and dependencies
RUN apt-get update && apt-get install -y \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libpq-dev \
    libxml2-dev \
    libzip-dev \
    unzip \
    git \
    curl \
    npm \
    nodejs \
    && docker-php-ext-install -j$(nproc) \
    mysqli \
    pdo_mysql \
    xml \
    zip \
    soap \
    calendar \
    exif \
    # Enable GD with freetype and jpeg support
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Set memory limits
RUN echo "memory_limit=-1" > /usr/local/etc/php/conf.d/memory-limit.ini

# Set up GitHub authentication if token is provided
ARG GITHUB_TOKEN
RUN if [ -n "$GITHUB_TOKEN" ]; then \
      composer config -g github-oauth.github.com ${GITHUB_TOKEN}; \
    else \
      echo "No GitHub token provided, skipping GitHub authentication"; \
    fi

# Clone OpenEMR repository
RUN git clone https://github.com/openemr/openemr.git /var/www/localhost/htdocs/openemr

# Set the working directory
WORKDIR /var/www/localhost/htdocs/openemr

# Download OpenEMR codebase first
RUN curl -L https://github.com/openemr/openemr/archive/refs/tags/v7.0.0.tar.gz | tar xz --strip-components=1

# Install composer dependencies
RUN composer install --no-dev

# Install NPM dependencies and build frontend assets
RUN npm install && npm run build

# Copy your custom code over the OpenEMR base
COPY . /var/www/localhost/htdocs/openemr/custom_code/

# Create necessary directories and set proper permissions
RUN mkdir -p /var/www/localhost/htdocs/openemr/sites/default && \
    chmod 755 /var/www/localhost/htdocs/openemr/sites && \
    chmod 755 /var/www/localhost/htdocs/openemr/sites/default && \
    touch /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php && \
    chmod 666 /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php && \
    chown -R www-data:www-data /var/www/localhost/htdocs/openemr

# Expose port 9000 for PHP-FPM
EXPOSE 9000

# Start PHP-FPM
CMD ["php-fpm"]
EOF

# Create nginx.conf
echo "Creating nginx.conf..."
cat > nginx.conf << 'EOF'
server {
    listen 80;
    server_name localhost;
    root /var/www/localhost/htdocs/openemr;
    
    index index.php index.html;
    
    # Increase client body size for file uploads
    client_max_body_size 100M;
    
    # Add debug info for troubleshooting
    error_log /var/log/nginx/openemr_error.log debug;
    access_log /var/log/nginx/openemr_access.log;
    
    location / {
        try_files $uri /index.php$is_args$args;
    }
    
    location ~* \.(jpg|jpeg|gif|png|css|js|ico|xml)$ {
        access_log off;
        log_not_found off;
        expires 30d;
    }
    
    location ~ \.php$ {
        fastcgi_pass openemr:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 300;
    }
    
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

# Create mysql-init.sql
echo "Creating mysql-init.sql..."
cat > mysql-init.sql << 'EOF'
-- Grant permissions to root from any host
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- Make sure openemr user has proper permissions
CREATE USER IF NOT EXISTS 'openemr'@'%' IDENTIFIED BY 'openemr';
GRANT ALL PRIVILEGES ON openemr.* TO 'openemr'@'%';

FLUSH PRIVILEGES;
EOF

# Create docker-compose.custom.yml
echo "Creating docker-compose.custom.yml..."
cat > docker-compose.custom.yml << 'EOF'
version: "3.1"
services:
    mysql:
        restart: always
        image: mariadb:11.4
        command:
            [
                "mariadbd",
                "--character-set-server=utf8mb4",
                "--skip-ssl",
                "--ssl-ca=/etc/ssl/ca.pem",
                "--ssl_cert=/etc/ssl/server-cert.pem",
                "--ssl_key=/etc/ssl/server-key.pem",
                "--bind-address=0.0.0.0"
            ]
        ports:
            - 3307:3306
        volumes:
            - databasevolume:/var/lib/mysql
            - ./mysql-init.sql:/docker-entrypoint-initdb.d/mysql-init.sql:ro
            - ./docker/library/sql-ssl-certs-keys/easy/ca.pem:/etc/ssl/ca.pem:ro
            - ./docker/library/sql-ssl-certs-keys/easy/server-cert.pem:/etc/ssl/server-cert.pem:ro
            - ./docker/library/sql-ssl-certs-keys/easy/server-key.pem:/etc/ssl/server-key.pem:ro
        environment:
            MYSQL_ROOT_PASSWORD: root
            MYSQL_USER: openemr
            MYSQL_PASSWORD: openemr
            MYSQL_DATABASE: openemr
            MYSQL_ROOT_HOST: "%"
        healthcheck:
            test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-proot"]
            interval: 10s
            timeout: 5s
            retries: 5

    openemr:
        restart: always
        image: registry.314ecorp.tech/openemr:latest
        user: root
        expose:
            - 9000
        volumes:
            - sitesvolume:/var/www/localhost/htdocs/openemr/sites:rw
            - logvolume:/var/log
            - configvolume:/var/www/localhost/htdocs/openemr/sites/default:rw
            - assetvolume:/var/www/localhost/htdocs/openemr/public/assets:rw
            - themevolume:/var/www/localhost/htdocs/openemr/public/themes:rw
        environment:
            MYSQL_HOST: mysql
            MYSQL_ROOT_PASS: root
            MYSQL_USER: openemr
            MYSQL_PASS: openemr
            OE_USER: admin
            OE_PASS: pass
            EASY_DEV_MODE: "yes"
            EASY_DEV_MODE_NEW: "yes"
            FORCE_NO_BUILD_MODE: "yes"
            DEVELOPER_TOOLS: "yes"
            INSANE_DEV_MODE: "yes"
            SKIP_DEMO_DATA: "false"
            DEMO_DATA: "true"
            OPENEMR_SETTING_couchdb_host: couchdb
            OPENEMR_SETTING_couchdb_port: 6984
            OPENEMR_SETTING_couchdb_user: admin
            OPENEMR_SETTING_couchdb_pass: password
            OPENEMR_SETTING_couchdb_dbase: example
            OPENEMR_SETTING_couchdb_ssl_allow_selfsigned: 1
        depends_on:
            mysql:
                condition: service_healthy

    phpmyadmin:
        restart: always
        image: phpmyadmin
        ports:
            - 8310:80
        environment:
            PMA_HOSTS: mysql
            PMA_PORT: 3306
        depends_on:
            mysql:
                condition: service_healthy

    couchdb:
        restart: always
        image: couchdb
        ports:
            - 5984:5984
            - 6984:6984
        volumes:
            - ./docker/library/couchdb-config-ssl-cert-keys/local.ini:/opt/couchdb/etc/local.ini:rw
            - ./docker/library/couchdb-config-ssl-cert-keys/easy/ca.pem:/etc/ssl/ca.pem:ro
            - ./docker/library/couchdb-config-ssl-cert-keys/easy/server-cert.pem:/etc/ssl/server-cert.pem:ro
            - ./docker/library/couchdb-config-ssl-cert-keys/easy/server-key.pem:/etc/ssl/server-key.pem:ro
            - couchdbvolume:/opt/couchdb/data
        environment:
            COUCHDB_USER: admin
            COUCHDB_PASSWORD: password

    nginx:
        image: nginx:latest
        ports:
            - 80:80
            - 443:443
        volumes:
            - ./nginx.conf:/etc/nginx/conf.d/default.conf
            - sitesvolume:/var/www/localhost/htdocs/openemr/sites:ro
            - assetvolume:/var/www/localhost/htdocs/openemr/public/assets:ro
            - themevolume:/var/www/localhost/htdocs/openemr/public/themes:ro
            - openemrroot:/var/www/localhost/htdocs/openemr:ro
        depends_on:
            - openemr

volumes:
    assetvolume: {}
    themevolume: {}
    databasevolume: {}
    sitesvolume: {}
    logvolume: {}
    couchdbvolume: {}
    configvolume: {}
    openemrroot: {}
EOF

# Create deployment script
echo "Creating deploy_custom_openemr.sh..."
cat > deploy_custom_openemr.sh << 'EOF'
#!/bin/bash
set -e

echo "======== OpenEMR Custom Deployment Script ========"

# Step 1: Create mysql-init.sql
echo -e "\n==== CREATING MYSQL INIT SCRIPT ===="
cat > mysql-init.sql << 'EOFINNER'
-- Grant permissions to root from any host
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- Make sure openemr user has proper permissions
CREATE USER IF NOT EXISTS 'openemr'@'%' IDENTIFIED BY 'openemr';
GRANT ALL PRIVILEGES ON openemr.* TO 'openemr'@'%';

FLUSH PRIVILEGES;
EOFINNER
echo "Created mysql-init.sql"

# Step 2: Create an updated nginx.conf
echo -e "\n==== CREATING NGINX CONFIGURATION ===="
cat > nginx.conf << 'EOFINNER'
server {
    listen 80;
    server_name localhost;
    root /var/www/localhost/htdocs/openemr;
    
    index index.php index.html;
    
    # Increase client body size for file uploads
    client_max_body_size 100M;
    
    # Add debug info for troubleshooting
    error_log /var/log/nginx/openemr_error.log debug;
    access_log /var/log/nginx/openemr_access.log;
    
    location / {
        try_files $uri /index.php$is_args$args;
    }
    
    location ~* \.(jpg|jpeg|gif|png|css|js|ico|xml)$ {
        access_log off;
        log_not_found off;
        expires 30d;
    }
    
    location ~ \.php$ {
        fastcgi_pass openemr:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 300;
    }
    
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOFINNER
echo "Created nginx.conf"

# Step 3: Start the containers
echo -e "\n==== STARTING CONTAINERS ===="
docker-compose -f docker-compose.custom.yml up -d

# Step 4: Wait for services to start
echo "Waiting for services to start..."
sleep 15

# Step 5: Initialize the container
echo -e "\n==== INITIALIZING OPENEMR CONTAINER ===="
CONTAINER_ID=$(docker-compose -f docker-compose.custom.yml ps -q openemr)

docker exec -it $CONTAINER_ID sh -c '
  # Create and initialize sqlconf.php
  mkdir -p /var/www/localhost/htdocs/openemr/sites/default
  
  echo "<?php
// This is a placeholder sqlconf.php that will be replaced by setup
\$host       = \"mysql\";
\$port       = 3306;
\$login      = \"openemr\";
\$pass       = \"openemr\";
\$dbase      = \"openemr\";
\$disable_utf8_flag = false;
\$config = 0;
?>" > /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php
  
  # Set permissions
  chmod 666 /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php
  chmod -R 755 /var/www/localhost/htdocs/openemr/sites
  chmod 777 /var/www/localhost/htdocs/openemr/sites/default
  
  echo "OpenEMR container initialized."
'

echo -e "\n\n==== SETUP COMPLETE ===="
echo "OpenEMR should now be available at: http://localhost"
echo "phpMyAdmin available at: http://localhost:8310"
echo "Default credentials: admin / pass"
EOF
chmod +x deploy_custom_openemr.sh

# Create CI workflow directory and file
echo "Creating GitHub Action workflow..."
mkdir -p .github/workflows
cat > .github/workflows/build-app-image.yml << 'EOF'
name: Build and Deploy OpenEMR Image

on:
  push:
    branches: [ main, feature/test ]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
        
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Private Registry
        uses: docker/login-action@v3
        with:
          registry: registry.314ecorp.tech
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}
          
      - name: Build and push OpenEMR image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile.simple
          build-args: |
            GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}
          tags: registry.314ecorp.tech/openemr:latest,registry.314ecorp.tech/openemr:${{ github.sha }}
          platforms: linux/amd64,linux/arm64
          push: true
          cache-from: type=registry,ref=registry.314ecorp.tech/openemr:latest
          cache-to: type=inline
EOF

echo -e "\n\n==== WOULD YOU LIKE TO BUILD AND PUSH THE DOCKER IMAGE? (y/n) ===="
read -r build_image
if [ "$build_image" = "y" ]; then
  echo "Building Docker image locally..."
  docker build -t registry.314ecorp.tech/openemr:latest -f Dockerfile.simple .
  
  echo "Would you like to push the image to registry.314ecorp.tech? (y/n)"
  read -r push_image
  if [ "$push_image" = "y" ]; then
    echo "Pushing Docker image to registry..."
    docker push registry.314ecorp.tech/openemr:latest
  fi
fi

echo -e "\n\n==== WOULD YOU LIKE TO START THE DEPLOYMENT? (y/n) ===="
read -r start_deploy
if [ "$start_deploy" = "y" ]; then
  echo "Starting deployment..."
  ./deploy_custom_openemr.sh
else
  echo -e "\n\n==== SETUP COMPLETE (DEPLOYMENT NOT STARTED) ===="
  echo "To deploy later, run:"
  echo "./deploy_custom_openemr.sh"
fi 