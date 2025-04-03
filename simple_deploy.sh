#!/bin/bash
set -e

echo "======== OpenEMR Simple Deployment Script ========"

# Create mysql-init.sql for basic database setup
cat > mysql-init.sql << 'EOF'
-- Grant permissions to root from any host
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- Make sure openemr user has proper permissions
CREATE USER IF NOT EXISTS 'openemr'@'%' IDENTIFIED BY 'openemr';
GRANT ALL PRIVILEGES ON openemr.* TO 'openemr'@'%';

FLUSH PRIVILEGES;
EOF
echo "Created mysql-init.sql"

# Create the docker-compose file
cat > docker-compose.simple.yml << 'EOF'
version: '3.1'
services:
  mysql:
    restart: always
    image: mariadb:11.4
    command: 
      - 'mariadbd'
      - '--character-set-server=utf8mb4'
      - '--bind-address=0.0.0.0'
    ports:
      - 3307:3306
    volumes:
      - databasevolume:/var/lib/mysql
      - ./mysql-init.sql:/docker-entrypoint-initdb.d/mysql-init.sql:ro
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
    ports:
      - 80:80
      - 443:443
    volumes:
      - sitesvolume:/var/www/localhost/htdocs/openemr/sites:rw
      - logvolume:/var/log
    environment:
      MYSQL_HOST: mysql
      MYSQL_ROOT_PASS: root
      MYSQL_USER: openemr
      MYSQL_PASS: openemr
      OE_USER: admin
      OE_PASS: pass
      EASY_DEV_MODE: "yes"
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

volumes:
  databasevolume: {}
  sitesvolume: {}
  logvolume: {}
EOF
echo "Created docker-compose.simple.yml"

# Stop any running containers
echo "Stopping any running OpenEMR containers..."
docker-compose down -v 2>/dev/null || true

# Start containers with the new configuration
echo "Starting OpenEMR with simple configuration..."
docker-compose -f docker-compose.simple.yml up -d

echo "Waiting for services to start..."
sleep 15

echo "Checking container status:"
docker-compose -f docker-compose.simple.yml ps

echo -e "\n\n==== SETUP COMPLETE ===="
echo "OpenEMR should now be available at: http://localhost"
echo "phpMyAdmin available at: http://localhost:8310"
echo "Default credentials: admin / pass" 