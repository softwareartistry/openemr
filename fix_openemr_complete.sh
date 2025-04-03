#!/bin/bash
set -e

echo "======== OpenEMR Complete Fix Script ========"

# Create a completely new docker-compose file using the official OpenEMR image
echo -e "\n==== CREATING NEW DOCKER COMPOSE CONFIGURATION ===="
cat > docker-compose.official.yml << 'EOF'
version: "3.1"
services:
  mysql:
    restart: always
    image: mariadb:11.4
    command: [
      "mariadbd",
      "--character-set-server=utf8mb4",
      "--skip-ssl",
      "--bind-address=0.0.0.0"
    ]
    ports:
      - 3307:3306
    volumes:
      - databasevolume:/var/lib/mysql
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
    ports:
      - 80:80
      - 443:443
    volumes:
      - sitesvolume:/var/www/localhost/htdocs/openemr/sites:rw
      - assetsvolume:/var/www/localhost/htdocs/openemr/public/assets:rw
      - themesvolume:/var/www/localhost/htdocs/openemr/public/themes:rw
      - logvolume:/var/log
    environment:
      MYSQL_HOST: mysql
      MYSQL_ROOT_PASS: root
      MYSQL_USER: openemr
      MYSQL_PASS: openemr
      OE_USER: admin
      OE_PASS: pass
      EASY_DEV_MODE: "yes"
      DEVELOPER_TOOLS: "yes"
      INSANE_DEV_MODE: "yes"
      DEMO_DATA: "true"
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

volumes:
  sitesvolume: {}
  databasevolume: {}
  logvolume: {}
  assetsvolume: {}
  themesvolume: {}
EOF

echo "Created docker-compose.official.yml with simplified, official OpenEMR configuration"

echo -e "\n==== WOULD YOU LIKE TO SWITCH TO THIS CONFIGURATION? (y/n) ===="
read -r use_official

if [ "$use_official" = "y" ]; then
  echo "Stopping all existing containers..."
  docker-compose -f docker-compose.custom.yml down -v || true
  
  echo "Starting with new official configuration..."
  docker-compose -f docker-compose.official.yml up -d
  
  echo "Waiting for services to start..."
  sleep 15
  
  echo "Checking container status:"
  docker-compose -f docker-compose.official.yml ps
fi

echo -e "\n\n==== SCRIPT COMPLETE ===="
echo "OpenEMR should now be available directly at: http://localhost"
echo "phpMyAdmin available at: http://localhost:8310"
echo "Default credentials: admin / pass" 