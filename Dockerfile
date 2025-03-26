# Build stage
FROM openemr/dev-php-fpm:pre-build-dev-85 as builder

WORKDIR /var/www/localhost/htdocs/openemr
COPY . .

# Install composer dependencies
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer install --no-dev --optimize-autoloader \
    && composer dump-autoload -o

# Production stage
FROM openemr/dev-php-fpm:pre-build-dev-85 as production

WORKDIR /var/www/localhost/htdocs/openemr
# Copy only necessary files from builder
COPY --from=builder /var/www/localhost/htdocs/openemr .

# Set proper permissions
RUN chown -R www-data:www-data .

# Expose ports
EXPOSE 80 443

# Start application
CMD ["php-fpm"] 