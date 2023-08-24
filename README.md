# ubernerd
Run Docker and LXC-like containers with a portable install of [nerdctl](https://github.com/containerd/nerdctl) on systemd based hosts.

## Goal
To extend (and not break) the capabilities of a systemd based Linux system, when modifying the rootfs is undesirable. For example a [TrueNAS SCALE](https://www.truenas.com/truenas-scale/) installation, which will lose all modifications to the rootfs, such as installing packages, after upgrading.

## Portable
A portable installation of `ubernerd` is nothing more than the latest version of `nerdctl`, unpacked in a directory of your choice (e.g. on a ZFS dataset under `/mnt`) with config files to store everything (containers, images, volumes etc.) inside this directory.

## Persistent containers (like LXC or FreeBSD Jails)
Thanks to the `--rootfs` option in `nerdctl`, you can run a full blown OS with init system. Modifications made inside these containers (e.g. installing packages) will persist. This is akin to a Virtual Machine, but with less isolation and overhead (RAM, CPU). You can have direct access to all the files on the host thanks to bind mounts. You can even make this container appear as a dedicated machine on your LAN and have its IP address assigned via DHCP in [`macvlan` networking mode](https://github.com/containerd/nerdctl/blob/main/docs/cni.md#macvlanipvlan-networks).

## Non-persistent containers (Docker)
Run docker containers directly using `nerdctl`. People familiar with `docker` and `compose` should feel right at home. However if you want to run anything which relies on the `docker.sock` (Docker API), like [portainer](https://github.com/portainer/portainer/issues/5964), then you may first create a [persistent container](#persistent-containers-like-lxc-or-freebsd-jails) and then install docker inside it according to the [regular installation instructions](https://docs.docker.com/engine/install/#server). Read the [nerdctl](https://github.com/containerd/nerdctl) documentation for more info on the compatibility and differences with docker.

## Installation

### TrueNAS SCALE
Setup a Post Init Script with Type `Command` from the TrueNAS web interface.