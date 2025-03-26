# Build stage - use debian base image directly and build PHP environment
FROM debian:bullseye-slim as php-base

# Copy PHP build configuration from your local dev-php-fpm Dockerfile
COPY docker/library/dockers/dev-php-fpm/data /usr/local/docker-data
COPY docker/library/dockers/dev-php-fpm/Dockerfile /tmp/php-fpm.Dockerfile

# Install PHP build dependencies and build PHP
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        autoconf \
        build-essential \
        ca-certificates \
        curl \
        git \
        libargon2-dev \
        libcurl4-openssl-dev \
        libedit-dev \
        libffi-dev \
        libonig-dev \
        libreadline-dev \
        libsodium-dev \
        libsqlite3-dev \
        libssl-dev \
        libxml2-dev \
        zlib1g-dev; \
    mkdir -p /usr/local/etc/php/conf.d /usr/local/bin; \
    cp /usr/local/docker-data/docker-php-* /usr/local/bin/; \
    chmod +x /usr/local/bin/docker-php-*; \
    rm -rf /var/lib/apt/lists/*

FROM php-base as builder

WORKDIR /var/www/localhost/htdocs/openemr
COPY . .

# Install composer dependencies
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer install --no-dev --optimize-autoloader \
    && composer dump-autoload -o

# Production stage - use the same php-base
FROM php-base as production

WORKDIR /var/www/localhost/htdocs/openemr
# Copy only necessary files from builder
COPY --from=builder /var/www/localhost/htdocs/openemr .

# Set proper permissions
RUN chown -R www-data:www-data .

# Expose ports
EXPOSE 80 443

# Start application
CMD ["php-fpm"] 