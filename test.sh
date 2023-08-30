#!/usr/bin/env bash

# Run this script to locally test the ubernerd.sh script during development
# Requires docker to be installed

set -euo pipefail

show_error() {
    docker stop ubernerd-test > /dev/null 2>&1 || true
	echo "Error while testing ubernerd installation :("
}

trap show_error ERR

echo "Start test script!"

# Create a local cache of the downloaded and extracted nerdctl binaries to save time
mkdir -p /tmp/ubernerd-test
# Test ubernerd installation inside a container with systemd init enabled
docker run -d --name ubernerd-test --privileged -v /tmp/ubernerd-test:/root/nerdctl_full -v ./ubernerd.sh:/root/ubernerd.sh:ro -w /root --rm almalinux/9-init
docker exec ubernerd-test ./ubernerd.sh

# Use --network=host because there is no iptables in this image
# Use --snapshotter=native because overlayfs doesn't seem to work inside the container:
# FATA[0000] failed to create shim task: failed to mount rootfs component: invalid argument: unknown 
docker exec ubernerd-test ./nerdctl run --network=host --snapshotter=native hello-world
docker stop ubernerd-test > /dev/null 2>&1

echo "Successfully passed ubernerd installation test!"