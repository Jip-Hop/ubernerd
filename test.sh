#!/usr/bin/env bash

# Run this script to locally test the ubernerd.sh script during development
# Requires docker to be installed

set -euo pipefail

show_error() {
    docker stop ubernerd >/dev/null 2>&1 || true
    echo "Error while testing ubernerd installation :("
}

trap show_error ERR

echo "Start test script!"

# Test ubernerd installation inside a container with systemd init enabled
# Use a named volume to prevent issues with the OverlayFS snapshotter on Docker Desktop on macOS
# Additionally, this volumes serves as a cache between runs to save time
# Manually delete this volume to start testing from scratch
docker run -d --rm --privileged --name ubernerd --mount source=ubernerd,target=/ubernerd -w /ubernerd almalinux/9-init
# Copy the latest ubernerd.sh script inside the container
docker cp ubernerd.sh ubernerd:/ubernerd
# Create the symlink and allow upgrading to the latest nerdctl version
docker exec -e CREATE_SYMLINK=1 -e UBERNERD_UPGRADE=1 ubernerd ./ubernerd.sh
# Use -w to run from a different working directory to test the symlink
# Use --network=host because there is no iptables in this image
docker exec -w /tmp ubernerd nerdctl run --network=host hello-world
docker stop ubernerd >/dev/null 2>&1

echo "Successfully passed ubernerd installation test!"
