#!/usr/bin/env bash

# Run this script to locally test the ubernerd.sh script during development
# Requires docker to be installed

set -euo pipefail

show_error() {
    docker stop ubernerd-test >/dev/null 2>&1 || true
    echo "Error while testing ubernerd installation :("
}

trap show_error ERR

echo "Start test script!"

# Create a local cache to keep between runs to save time
mkdir -p /tmp/ubernerd-test
# Copy the ubernerd.sh script into the test dir (so we can change permissions etc.)
cp ubernerd.sh /tmp/ubernerd-test/
# Test ubernerd installation inside a container with systemd init enabled
docker run -d --name ubernerd-test --privileged -v /tmp/ubernerd-test:/root/ubernerd-test -w /root/ubernerd-test --rm almalinux/9-init
# Create the symlink, to test running from a different working directory
docker exec -e CREATE_SYMLINK=1 -e UBERNERD_UPGRADE=1 ubernerd-test ./ubernerd.sh

# Use -w to run from a different working directory to test the symlink
# Use --network=host because there is no iptables in this image
# Use --snapshotter=native because overlayfs doesn't seem to work inside the container:
# FATA[0000] failed to create shim task: failed to mount rootfs component: invalid argument: unknown
docker exec -w /tmp ubernerd-test nerdctl run --network=host --snapshotter=native hello-world
docker stop ubernerd-test >/dev/null 2>&1

echo "Successfully passed ubernerd installation test!"
