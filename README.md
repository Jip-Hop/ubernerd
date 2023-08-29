# ubernerd
Run Docker and LXC-like containers with a portable install of [nerdctl](https://github.com/containerd/nerdctl) on systemd based hosts.

## Disclaimer

**USING THIS SCRIPT IS AT YOUR OWN RISK! IT COMES WITHOUT WARRANTY. THIS HAS NOT YET BEEN EXTENSIVELY TESTED!**

## Goal
To extend (and not break) the capabilities of a systemd based Linux system, when modifying the rootfs is undesirable. For example a [TrueNAS SCALE](https://www.truenas.com/truenas-scale/) installation, which will lose all modifications to the rootfs, such as installing packages, after upgrading.

## Portable
A portable installation of `ubernerd` is nothing more than the latest version of `nerdctl`, unpacked in a directory of your choice (e.g. on a ZFS dataset under `/mnt`) with config files to store everything (containers, images, volumes etc.) inside this directory.

## Persistent containers (like LXC or FreeBSD Jails)
Thanks to the `--rootfs` option in `nerdctl`, you can run a full blown OS with init system. Modifications made inside these containers (e.g. installing packages) will persist. This is akin to a Virtual Machine, but with less isolation and overhead (RAM, CPU). You can have direct access to all the files on the host thanks to bind mounts. You can even make this container appear as a dedicated machine on your LAN and have its IP address assigned via DHCP in [`macvlan` networking mode](https://github.com/containerd/nerdctl/blob/main/docs/cni.md#macvlanipvlan-networks).

## Non-persistent containers (Docker)
Run docker containers directly using `nerdctl`. People familiar with `docker` and `compose` should feel right at home. However if you want to run anything which relies on the `docker.sock` (Docker API), like [portainer](https://github.com/portainer/portainer/issues/5964), then you may first create a [persistent container](#persistent-containers-like-lxc-or-freebsd-jails) and then install docker inside it according to the [regular installation instructions](https://docs.docker.com/engine/install/#server). Read the [nerdctl](https://github.com/containerd/nerdctl) documentation for more info on the compatibility, extra features and other differences with docker.

## Requirements
- bash
- systemd
- iptables
- coreutils
- curl or wget (optional)
- tar (optional)

## Installation

Create a directory where you want to store `ubernerd.sh`, config and data. E.g. on an externally connected SSD formatted as `ext4` or on a ZFS dataset: `/mnt/tank/ubernerd`. Download the script into this directory.

```
cd /mnt/tank/ubernerd
curl --location --remote-name https://raw.githubusercontent.com/Jip-Hop/ubernerd/main/ubernerd.sh
chmod +x ubernerd.sh
```

You'll have to run `ubernerd.sh` to complete the installation and start the `containerd` process.

## Running containerd and nerdctl

If you run `ubernerd.sh`, it will check if the installation is complete. If not it will complete the installation by downloading the full set of `nerdctl` executables/dependencies. Finally it will start the `containerd` process. From then on you can run the `./nerdctl` command from inside your `ubernerd` directory.

### Without modifying host rootfs

To download the full set of `nerdctl` executables/dependencies and start `containerd`, without modifying the host rootfs, run:

```
./ubernerd.sh
```

### Creating convenience symlink (modifies host rootfs)

Alternatively you may call `ubernerd.sh` with the `CREATE_SYMLINK` environment variable to 1, to allow creating a symlink at `/usr/local/sbin/nerdctl`. Technically this breaks the promise of 'not modifying the host rootfs', but it may be a good tradeoff for the convenience of being able to call the `nerdctl` command regardless of the directory you're in. If you want to keep the symlink updated (in case you'll ever move your `ubernerd` directory) it is recommended to always start `ubernerd.sh` with `CREATE_SYMLINK=1`.

```
CREATE_SYMLINK=1 ./ubernerd.sh
```

### Running nerdctl commands
From inside the `ubernerd` directory you may now call `./nerdctl` commands.

```
./nerdctl run hello-world
```

If you've chosen to create a symlink you may run it from anywhere.

```
nerdctl run hello-world
```

### TrueNAS SCALE
Run `ubernerd.sh` as Post Init Script with Type `Command` from the TrueNAS web interface. E.g. `/mnt/tank/ubernerd/ubernerd.sh` or `CREATE_SYMLINK=1 /mnt/tank/ubernerd/ubernerd.sh` and change the path according to your situation.