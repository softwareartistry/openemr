#!/bin/bash
set -e

echo "======== OpenEMR Permissions Fix Script ========"

echo -e "\n\n==== CREATING PERMISSION FIX SCRIPT ===="
cat > fix_container_permissions.sh << 'EOF'
#!/bin/bash
# This script fixes permissions in the OpenEMR container

# Get container ID
CONTAINER_ID=$(docker-compose -f docker-compose.fixed.yml ps -q openemr)

if [ -z "$CONTAINER_ID" ]; then
  echo "Error: OpenEMR container not found"
  exit 1
fi

echo "Fixing permissions for OpenEMR container..."

# Fix permissions on key directories
docker exec -it $CONTAINER_ID sh -c '
  mkdir -p /var/www/localhost/htdocs/openemr/sites/default
  chmod 755 /var/www/localhost/htdocs/openemr/sites
  chmod 755 /var/www/localhost/htdocs/openemr/sites/default
  
  # Make sure directories are owned by the web server user (apache in Alpine)
  chown -R apache:apache /var/www/localhost/htdocs/openemr/sites
  chown -R apache:apache /var/www/localhost/htdocs/openemr/sites/default
  
  # Touch the sqlconf file if it doesn't exist
  if [ ! -f /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php ]; then
    touch /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php
    chown apache:apache /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php
    chmod 644 /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php
  fi
  
  echo "Permissions fixed."
'
EOF

chmod +x fix_container_permissions.sh
echo "Created fix_container_permissions.sh"

# Update the docker-compose file
echo -e "\n\n==== UPDATING DOCKER COMPOSE ===="
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
        user: root
        expose:
            - 9000
        volumes:
            - assetvolume:/var/www/localhost/htdocs/openemr/public/assets:rw
            - themevolume:/var/www/localhost/htdocs/openemr/public/themes:rw
            - sitesvolume:/var/www/localhost/htdocs/openemr/sites:rw
            - nodemodules:/var/www/localhost/htdocs/openemr/node_modules:rw
            - logvolume:/var/log
            - configvolume:/var/www/localhost/htdocs/openemr/sites/default:rw
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

echo "Updated docker-compose.fixed.yml with correct permissions settings"

echo -e "\n\n==== WOULD YOU LIKE TO RESTART WITH THE NEW CONFIGURATION? (y/n) ===="
read -r restart_config
if [ "$restart_config" = "y" ]; then
  echo "Stopping current containers..."
  docker-compose -f docker-compose.fixed.yml down -v
  
  echo "Starting with new configuration..."
  docker-compose -f docker-compose.fixed.yml up -d
  
  echo "Waiting for services to start..."
  sleep 15
  
  echo "Running permissions fix script..."
  ./fix_container_permissions.sh
  
  echo -e "\n\n==== SETUP COMPLETE ===="
  echo "OpenEMR should now be available at: http://localhost"
  echo "phpMyAdmin available at: http://localhost:8310"
  echo "Default credentials: admin / pass"
fi 