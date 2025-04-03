#!/bin/bash
set -e

echo "======== OpenEMR Custom Deployment Script ========"

# Step 1: Create mysql-init.sql
echo -e "\n==== CREATING MYSQL INIT SCRIPT ===="
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

# Step 2: Create an updated nginx.conf
echo -e "\n==== CREATING NGINX CONFIGURATION ===="
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