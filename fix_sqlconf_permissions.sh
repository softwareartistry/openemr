#!/bin/bash
set -e

echo "======== OpenEMR SQLConf Permissions Fix Script ========"

# Get container ID
CONTAINER_ID=$(docker-compose -f docker-compose.custom.yml ps -q openemr)

if [ -z "$CONTAINER_ID" ]; then
  echo "Error: OpenEMR container not found"
  exit 1
fi

echo "Fixing SQLConf permissions for OpenEMR container..."

# Create and set proper permissions for the sqlconf.php file
docker exec -it $CONTAINER_ID sh -c '
  # Create directory structure if it doesn't exist
  mkdir -p /var/www/localhost/htdocs/openemr/sites/default
  
  # Create sample sqlconf.php if it doesn't exist
  if [ ! -f /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php ]; then
    echo "<?php
// This is a placeholder sqlconf.php that will be replaced by setup
// Created by fix script
\$host       = \"mysql\";
\$port       = 3306;
\$login      = \"openemr\";
\$pass       = \"openemr\";
\$dbase      = \"openemr\";
\$disable_utf8_flag = false;
?>" > /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php
  fi
  
  # Fix ownership and permissions
  chmod 666 /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php
  chmod -R 755 /var/www/localhost/htdocs/openemr/sites
  chmod 777 /var/www/localhost/htdocs/openemr/sites/default
  
  # Make sure both nginx and php-fpm can read the file
  # Apply broad permissions temporarily to diagnose the issue
  echo "Setting very permissive permissions (temporarily for troubleshooting)"
  chmod 777 /var/www/localhost/htdocs/openemr/sites/default/sqlconf.php
  
  # List the permissions to verify
  ls -la /var/www/localhost/htdocs/openemr/sites/default/
  
  echo "Permissions fixed."
'

echo "Restarting services..."
docker-compose -f docker-compose.custom.yml restart openemr nginx

echo -e "\n\n==== FIX COMPLETE ===="
echo "OpenEMR should now be able to access the sqlconf.php file."
echo "Try accessing OpenEMR at http://localhost" 