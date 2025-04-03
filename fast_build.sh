#!/bin/bash
set -e

echo "Building OpenEMR Docker image with optimizations..."

# Set environment variables to speed up Node and PHP processes
export NODE_OPTIONS="--max-old-space-size=4096"
export COMPOSER_MEMORY_LIMIT=-1

# Set platform specifically to avoid slow multi-platform builds
DOCKER_BUILDKIT=1 docker build \
  --build-arg FORK_USERNAME=softwareartistry \
  --build-arg FORK_BRANCH=master \
  --build-arg FORK_REPO=https://github.com/softwareartistry/openemr.git \
  --file Dockerfile.fast \
  --tag registry.314ecorp.tech/openemr:latest \
  --progress=plain \
  --platform linux/amd64 \
  --no-cache=false \
  --compress=true \
  .

echo "Build complete!" 