#!/bin/bash
set -e

echo "======== Updating Nginx Access for OpenEMR ========"

# Create an updated nginx.conf with enhanced permissions
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

echo "Updated nginx.conf with enhanced logging"

# Update the docker-compose file to mount the sites directory directly
cat > docker-compose.custom-updated.yml << 'EOF'
version: '3.1'
services:
  mysql:
    restart: always
    image: mariadb:11.4
    command: [
      'mariadbd',
      '--character-set-server=utf8mb4',
      '--skip-ssl',
      '--ssl-ca=/etc/ssl/ca.pem',
      '--ssl_cert=/etc/ssl/server-cert.pem',
      '--ssl_key=/etc/ssl/server-key.pem',
      '--bind-address=0.0.0.0'
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
    image: openemr/openemr:7.0.0
    user: root
    expose:
      - 9000
    volumes:
      - sitesvolume:/var/www/localhost/htdocs/openemr/sites:rw
      - logvolume:/var/log
      - configvolume:/var/www/localhost/htdocs/openemr/sites/default:rw
      - assetvolume:/var/www/localhost/htdocs/openemr/public/assets:rw
      - themevolume:/var/www/localhost/htdocs/openemr/public/themes:rw
      - ./:/var/www/localhost/htdocs/openemr/custom_code:ro
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
      - ./custom_root:/var/www/localhost/htdocs/openemr:ro
    depends_on:
      - openemr

volumes:
  databasevolume: {}
  sitesvolume: {}
  logvolume: {}
  couchdbvolume: {}
  configvolume: {}
  assetvolume: {}
  themevolume: {}
EOF

echo "Created updated docker-compose file"
echo "Would you like to switch to using the official OpenEMR image? (y/n)"
read -r use_official

if [ "$use_official" = "y" ]; then
  echo "Switching to official OpenEMR image..."
  cp docker-compose.custom-updated.yml docker-compose.custom.yml
  
  echo "Would you like to restart the containers with the new configuration? (y/n)"
  read -r restart_containers
  
  if [ "$restart_containers" = "y" ]; then
    echo "Stopping and removing existing containers..."
    docker-compose -f docker-compose.custom.yml down -v
    
    echo "Starting containers with new configuration..."
    docker-compose -f docker-compose.custom.yml up -d
    
    echo "Waiting for services to start..."
    sleep 15
    
    echo "Running SQLConf permission fix..."
    chmod +x fix_sqlconf_permissions.sh
    ./fix_sqlconf_permissions.sh
  fi
fi

echo -e "\n\n==== SCRIPT COMPLETE ===="
echo "If you didn't restart automatically, run the following commands:"
echo "1. docker-compose -f docker-compose.custom.yml down -v"
echo "2. docker-compose -f docker-compose.custom.yml up -d"
echo "3. ./fix_sqlconf_permissions.sh" 