#!/bin/bash
set -e

echo "======== OpenEMR Troubleshooting Script ========"

# Check container status
echo -e "\n\n==== CHECKING CONTAINER STATUS ===="
docker-compose -f docker-compose.custom.yml ps

# View container logs
echo -e "\n\n==== CHECKING OPENEMR CONTAINER LOGS ===="
docker-compose -f docker-compose.custom.yml logs openemr | tail -n 20

# Check if PHP-FPM is running in OpenEMR container
echo -e "\n\n==== CHECKING PHP-FPM PROCESS ===="
docker-compose -f docker-compose.custom.yml exec openemr ps aux | grep php-fpm

# Check network connectivity between containers
echo -e "\n\n==== CHECKING NETWORK CONNECTIVITY ===="
docker-compose -f docker-compose.custom.yml exec nginx ping -c 2 openemr

# Fix OpenEMR container if needed
echo -e "\n\n==== FIXING OPENEMR CONTAINER ===="
echo "Would you like to restart the OpenEMR container? (y/n)"
read -r restart_openemr
if [ "$restart_openemr" = "y" ]; then
  echo "Restarting OpenEMR container..."
  docker-compose -f docker-compose.custom.yml restart openemr
  
  # Wait for it to start up
  echo "Waiting for container to start up..."
  sleep 10
  
  # Check if it's running now
  echo "Checking if PHP-FPM is running now:"
  docker-compose -f docker-compose.custom.yml exec openemr ps aux | grep php-fpm
fi

# Update docker-compose to use a direct PHP image if needed
echo -e "\n\n==== WOULD YOU LIKE TO SWITCH TO A STANDARD PHP-FPM IMAGE? (y/n) ===="
read -r switch_image
if [ "$switch_image" = "y" ]; then
  echo "Creating new docker-compose file with standard PHP-FPM image..."
  
  # Create a backup
  cp docker-compose.custom.yml docker-compose.custom.yml.bak
  
  # Create a new docker-compose file with php:7.4-fpm
  cat > docker-compose.fixed.yml << 'EOF'
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
                "--bind-address=0.0.0.0",
            ]
        ports:
            - 3306:3306
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
        expose:
            - 9000
        volumes:
            - assetvolume:/var/www/localhost/htdocs/openemr/public/assets:rw
            - themevolume:/var/www/localhost/htdocs/openemr/public/themes:rw
            - sitesvolume:/var/www/localhost/htdocs/openemr/sites:rw
            - nodemodules:/var/www/localhost/htdocs/openemr/node_modules:rw
            - logvolume:/var/log
            - configvolume:/var/www/localhost/htdocs/openemr/sites/default
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
        depends_on:
            - openemr

volumes:
    assetvolume: {}
    nodemodules: {}
    themevolume: {}
    databasevolume: {}
    sitesvolume: {}
    logvolume: {}
    couchdbvolume: {}
    configvolume: {}
EOF
  
  echo "Created docker-compose.fixed.yml with official OpenEMR image"
  echo "Would you like to start containers with the new configuration? (y/n)"
  read -r start_fixed
  if [ "$start_fixed" = "y" ]; then
    echo "Stopping current containers..."
    docker-compose -f docker-compose.custom.yml down
    
    echo "Starting with new configuration..."
    docker-compose -f docker-compose.fixed.yml up -d
    
    echo "Waiting for services to start..."
    sleep 15
    
    echo "Checking container status:"
    docker-compose -f docker-compose.fixed.yml ps
  fi
fi

echo -e "\n\n==== TROUBLESHOOTING COMPLETE ===="
echo "If you're still experiencing issues, please try the following:"
echo "1. Check if PHP-FPM is running in the OpenEMR container"
echo "2. Verify the OpenEMR container is exposing port 9000"
echo "3. Check the OpenEMR container logs for any errors"
echo "4. Make sure networking between containers is working properly" 