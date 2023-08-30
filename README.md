# ubernerd
Run Docker and LXC-like containers with a portable install of [nerdctl](https://github.com/containerd/nerdctl) on systemd based hosts.

## Disclaimer

**USING THIS SCRIPT IS AT YOUR OWN RISK! IT COMES WITHOUT WARRANTY. THIS HAS NOT YET BEEN EXTENSIVELY TESTED!**

## Goal
To extend (and not break) the capabilities of a systemd based Linux system, when modifying the rootfs is undesirable. For example a [TrueNAS SCALE](https://www.truenas.com/truenas-scale/) installation, which will lose all modifications to the rootfs, such as installing packages, after upgrading.

## Portable
A portable installation of `ubernerd` is nothing more than the latest version of `nerdctl`, unpacked in a directory of your choice (e.g. on a ZFS dataset under `/mnt`) with config files to store everything (containers, images, volumes etc.) inside this directory.

## Persistent containers (like LXC, systemd-nspawn or FreeBSD Jails)
Thanks to the `--rootfs` option in `nerdctl`, you can run a full blown OS with init system. Modifications made inside these containers (e.g. installing packages) will persist. This is akin to a Virtual Machine, but with less isolation and overhead (RAM, CPU). You can have direct access to all the files on the host thanks to bind mounts. You can even make this container appear as a dedicated machine on your LAN and have its IP address assigned via DHCP in [`macvlan` networking mode](https://github.com/containerd/nerdctl/blob/main/docs/cni.md#macvlanipvlan-networks).

## Non-persistent containers (Docker)
Run docker containers directly using `nerdctl`. People familiar with `docker` and `compose` should feel right at home. However if you want to run anything which relies on the `docker.sock` (Docker API), like [portainer](https://github.com/portainer/portainer/issues/5964), then you may first create a [persistent container](#persistent-containers-like-lxc-systemd-nspawn-or-freebsd-jails) and then install docker inside it according to the [regular installation instructions](https://docs.docker.com/engine/install/#server). Read the [nerdctl](https://github.com/containerd/nerdctl) documentation for more info on the compatibility, extra features and other differences with docker.

## Requirements
- bash
- systemd
- coreutils
- iptables (except when using `--network=host` or `--network=none`)
- curl or wget (optional)
- tar (optional)
- root rights (currently ubernerd does not support rootless containers)

## Installation
Create a directory where you want to store `ubernerd.sh`, config and data. E.g. on an externally connected SSD formatted as `ext4` or on a ZFS dataset: `/mnt/tank/ubernerd`. Download the script into this directory.

```sh
cd /mnt/tank/ubernerd
curl --location --remote-name https://raw.githubusercontent.com/Jip-Hop/ubernerd/main/ubernerd.sh
chmod +x ubernerd.sh
```

You'll have to run `ubernerd.sh` to complete the installation and start the `containerd` process.

## Running containerd and nerdctl
If you run `ubernerd.sh`, it will check if the installation is complete. If not it will complete the installation by downloading the full set of `nerdctl` executables/dependencies. Finally it will start the `containerd` process. From then on you can run the `./nerdctl` command from inside your `ubernerd` directory.

### Without modifying host rootfs
To download the full set of `nerdctl` executables/dependencies and start `containerd`, without modifying the host rootfs, run:

```sh
./ubernerd.sh
```

### Creating convenience symlink (modifies host rootfs)
Alternatively you may call `ubernerd.sh` with the `CREATE_SYMLINK` environment variable to 1, to allow creating a symlink at `/usr/local/sbin/nerdctl`. Technically this breaks the promise of 'not modifying the host rootfs', but it may be a good tradeoff for the convenience of being able to call the `nerdctl` command regardless of the directory you're in. If you want to keep the symlink updated (in case you'll ever move your `ubernerd` directory) it is recommended to always start `ubernerd.sh` with `CREATE_SYMLINK=1`.

```sh
CREATE_SYMLINK=1 ./ubernerd.sh
```

### Running nerdctl commands
From inside the `ubernerd` directory you may now call `./nerdctl` commands.

```sh
./nerdctl run hello-world
```

If you've chosen to create a symlink you may run it from anywhere.

```sh
nerdctl run hello-world
```

## Examples

The following examples are suggestions. Adapt as you see fit.

### Persistent debian container with docker installed

Run these commands from inside a directory on persistent storage (not a temporary folder, or a directory which will be wiped on upgrades of your host OS).

```sh
# Unfortunately no `nerdctl container export` yet, so use crane instead to unpack a docker image
mkdir rootfs
nerdctl run --rm gcr.io/go-containerregistry/crane export debian - | tar xvC rootfs

# Install some packages in the container as well as docker
nerdctl run --rm --rootfs rootfs /bin/bash -c 'apt-get update && apt-get -y install init curl'
nerdctl run --rm --rootfs rootfs /bin/bash -c 'curl -fsSL https://get.docker.com | sh'

# Run the jail again, but this time fully 'boot' it by starting the init process
nerdctl run -d --restart unless-stopped --privileged --name debian --rootfs rootfs /sbin/init
# Open a shell in the container
nerdctl exec -it debian /bin/bash
```

This container will start automatically the next time you run `ubernerd.sh`, because it has the restart policy set to `unless-stopped`. To prevent the container from starting the next time, you should stop it manually.

## TrueNAS SCALE
Run `ubernerd.sh` as Post Init Script with Type `Command` from the TrueNAS web interface. E.g. `/mnt/tank/ubernerd/ubernerd.sh` or `CREATE_SYMLINK=1 /mnt/tank/ubernerd/ubernerd.sh` and change the path according to your situation.

## Why call it ubernerd?
That's what my girlfriend calls me when I can't stop thinking about this project. Coincidentally über (meaning "over", "above") expresses that this project is build on top of contai**nerd** and **nerd**ctl.

## Development
To automatically test the `ubernerd.sh` script, you may run `./test.sh`. It requires docker to be installed locally.