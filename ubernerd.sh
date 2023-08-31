#!/usr/bin/env bash

set -euo pipefail

# Set the CREATE_SYMLINK environment variable to 1 to make the nerdctl command available globally
# This will modify the host rootfs
CREATE_SYMLINK="${CREATE_SYMLINK:-0}"
UBERNERD_UPGRADE="${UBERNERD_UPGRADE:-0}"
# TODO: also check for newer version of ubernerd.sh script and upgrade when UBERNERD_UPGRADE is enabled
# TODO: allow a configurable namespace (default ubernerd) to prevent possible clashes on the filesystem
# with regards to the service file and socket path etc.

absolute_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_name=$(basename "${absolute_script_path}")
script_parent_dir="$(dirname "$absolute_script_path")"

# Function to show error message and line number
show_error() {
	local line=$1
	local line_content
	mapfile -s $((line - 1)) -n 1 -t line_content <"$absolute_script_path"
	echo "An error occurred in the script at line $line:"
	echo "${line_content[0]}"
}

# Trap the script exit and call the error message function
trap 'show_error $LINENO' ERR

fail() {
	echo -e "$1" >&2 && exit 1
}

[[ -z "${BASH_VERSINFO+x}" ]] && fail 'This script must run in bash...'
[[ $UID -ne 0 ]] && fail "Run this script as root..."

# Function to check if an executable is available
is_executable_available() {
	executable=$1

	# Check if the executable is available
	if type "$executable" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

get_timestamp() {
	date +%Y-%m-%d_%H-%M-%S
}

# TODO: should be possible to start containerd without systemd...
is_executable_available 'systemctl' || fail "systemctl is required but not available..."

# Check if ubernerd-containerd is already running, else don't continue and tell user to manually stop it first
if systemctl is-active --quiet "ubernerd-containerd"; then
	echo 'Abort: ubernerd-containerd is already running!'
	fail 'You may stop it with: systemctl stop ubernerd-containerd.'
else
	echo 'Welcome ubernerd!'
fi

cd "${script_parent_dir}" || fail "Could not change working directory to ${script_parent_dir}..."

stat_chmod() {
	# Only run chmod if mode is different from current mode
	if [[ "$(stat -c%a "${2}")" -ne "${1}" ]]; then chmod "${1}" "${2}"; fi
}

download() {
	local url=$1

	if is_executable_available 'wget'; then
		wget -qO- --tries=5 "$url"
	elif is_executable_available 'curl'; then
		curl -sSL --retry 5 "$url"
	else
		fail "Neither wget nor curl is installed. Please install either of them to proceed."
	fi
}

# Function to replace grep without external commands
mygrep() {
	pattern=$1

	# Read the input from pipe line by line
	while IFS= read -r line; do
		# Check if the line contains the pattern
		if [[ $line == *"$pattern"* ]]; then
			echo "$line"
		fi
	done
}

# Set appropriate permissions (if not already set) for this file, since it's executed as root
stat_chmod 700 "${script_name}"

# Prepend nerdctl binaries to path
export PATH="${script_parent_dir}/nerdctl_full/bin:${PATH}"

echo ''
echo "Creating directories (if necessary)..."

# List of directories to create
dir_list=("config/cni/net.d" "config/containerd" "config/nerdctl" "nerdctl_full" "state/containerd/root" "state/containerd/state" "state/nerdctl/data_root")

# Loop through the list and create directories
for dir_name in "${dir_list[@]}"; do
	mkdir -p --verbose "$dir_name"
done

get_nerdctl_latest_release_json() {
	download 'https://api.github.com/repos/containerd/nerdctl/releases/latest'
}

needs_download=0
nerdctl_latest_release_json=

# Check if containerd and nerdctl inside nerdctl_full, else download and extract latest release
# If UBERNERD_UPGRADE is enabled, check if upgrade is available too
if [[ -f 'nerdctl_full/bin/containerd' && -f 'nerdctl_full/bin/nerdctl' ]]; then
	echo ''
	echo 'Found containerd and nerdctl inside nerdctl_full directory.'

	if [[ "$UBERNERD_UPGRADE" -eq 1 ]]; then
		echo "Check if upgrade is available..."
		local_version="$(nerdctl_full/bin/nerdctl version -f '{{.Client.Version}}' 2>/dev/null)" || true

		nerdctl_latest_release_json=$(get_nerdctl_latest_release_json)

		remote_version="$(printf "%s" "$nerdctl_latest_release_json" | mygrep '"tag_name":')"
		pattern='v([0-9]+\.?)+'
		[[ $remote_version =~ $pattern ]]
		remote_version="${BASH_REMATCH[0]}"

		if [[ "$remote_version" != "$local_version" ]]; then
			echo "Local version: $local_version".
			echo "Remote version: $remote_version".
			echo "Needs to upgrade!"

			needs_download=1
			old_nerdctl_full="nerdctl_full_${local_version}_$(get_timestamp)"

			echo "Backing up current installation to $old_nerdctl_full"
			mv nerdctl_full "$old_nerdctl_full"
			mkdir nerdctl_full
		else
			echo "Already using the latest version: $remote_version".
		fi
	fi

else
	needs_download=1
	nerdctl_latest_release_json=$(get_nerdctl_latest_release_json)
fi

if [[ "$needs_download" -eq 1 ]]; then
	echo ''
	echo 'Need to download latest release of nerdctl...'

	manualy_download_extract_message='Please manually download the latest nerdctl-full from https://github.com/containerd/nerdctl/releases, extract it and place contents in the nerdctl_full directory.'

	if ! is_executable_available "wget" && ! is_executable_available "curl"; then
		echo ''
		echo "Neither wget or curl are avaialble."
		fail "$manualy_download_extract_message"
	fi

	if ! is_executable_available 'tar'; then
		echo ''
		echo 'The tar command is not available.'
		fail "$manualy_download_extract_message"
	fi

	arch=$(uname -m)

	if [[ $arch == "x86_64" ]]; then
		arch=amd64
		echo "Detected $arch architecture, downloading $arch version..."
	else
		arch=arm64
		echo "Assuming $arch architecture, downloading $arch version..."
	fi

	download_url="$(printf "%s" "$nerdctl_latest_release_json" | mygrep 'nerdctl-full-' | mygrep "-linux-$arch.tar.gz" | mygrep 'browser_download_url' | cut -d '"' -f 4)"

	echo ''
	echo "Downloading $download_url..."
	download "$download_url" | tar -xz -C 'nerdctl_full'
fi

# TODO: To support the opt plugin, the path variable needs to be dynamically set to a path
# inside our parent directory (to ensure portability). If we put a comment after the path value:

# [plugins]

#   [plugins."io.containerd.internal.v1.opt"]
#	 path = "/path/to/ubernerd/plugins/containerd" # MANAGED BY UBERNERD - DO NOT EDIT OR REMOVE THIS LINE

# Then we can search for this line with mygrep, and if the line has the wrong value we can update it.

if [[ ! -f 'config/containerd/config.toml' ]]; then
	echo 'Creating containerd config.toml file in config/containerd'

	cat <<-'EOF' >'config/containerd/config.toml'
		version = 2

		# cri is not used by nerdctl
		# opt needs a hard-coded absolute path to load plugins from (not portable) 
		disabled_plugins = ["io.containerd.grpc.v1.cri", "io.containerd.internal.v1.opt"]

		[grpc]
		address = "/run/ubernerd/containerd/containerd.sock"
	EOF
fi

# Create initial nerdctl.toml
if [[ ! -f 'config/nerdctl/nerdctl.toml' ]]; then
	echo 'Creating nerdctl.toml file in config/nerdctl'

	cat <<-'EOF' >'config/nerdctl/nerdctl.toml'
		address = "unix:///run/ubernerd/containerd/containerd.sock"
	EOF
fi

run_nerdctl() {
	ubernerd_dir=$(dirname "$(readlink -f "$0")")
	# Prepend nerdctl binaries to path
	export PATH="${ubernerd_dir}/nerdctl_full/bin:${PATH}"
	# Make nerdctl use our config file
	export NERDCTL_TOML="${ubernerd_dir}/config/nerdctl/nerdctl.toml"

	# Make nerdctl use custom directories and pass through all command line arguments
	nerdctl \
		--data-root "${ubernerd_dir}/state/nerdctl/data_root" \
		--cni-path "${ubernerd_dir}/nerdctl_full/libexec/cni" \
		--cni-netconfpath "${ubernerd_dir}/config/cni/net.d" \
		"$@"
}

nerdctl_script_contents='#!/usr/bin/env bash'

# Run the type command and store the output in an array
mapfile -s 3 -t lines < <(type -a run_nerdctl)
# Erase last line in the array
lines[${#lines[@]} - 1]=""

# Build the nerdctl wrapper script content
for line in "${lines[@]}"; do
	# Append each line of the type output to the script contents and strip leading spaces
	nerdctl_script_contents="${nerdctl_script_contents}"$'\n'"${line#"${line%%[![:space:]]*}"}"
done

# Create the nerdctl bash script (if not exists or contents are different)
if [[ ! -f nerdctl || ! "$(cat nerdctl)" = "$nerdctl_script_contents" ]]; then
	echo ''
	echo 'Creating nerdctl script'
	printf "%s" "$nerdctl_script_contents" >nerdctl
fi

# Make nerdctl executable if not already
stat_chmod 755 nerdctl

if [[ "${CREATE_SYMLINK}" -eq 1 ]]; then
	symlink_path=/usr/local/sbin/nerdctl
	correct_destination="${script_parent_dir}/nerdctl"

	if [[ ! -f /usr/local/sbin/nerdctl ]]; then
		echo ''
		echo 'Creating symlink for nerdctl...'
		ln -s "$correct_destination" "$symlink_path"
	elif [[ -L "$symlink_path" ]]; then
		if [[ "$(readlink "$symlink_path")" != "$correct_destination" ]]; then
			echo ''
			echo 'Updating symlink for nerdctl...'
			ln -sf "$correct_destination" "$symlink_path"
		fi
	else
		echo ''
		echo "File exists at $symlink_path but it is not a symlink..."
		echo 'Skipped creating symlink.'
	fi
else
	echo ''
	echo 'The CREATE_SYMLINK environment variable is not set to 1.'
	echo 'Skipped creating/updating nerdctl symlink.'
	echo 'By default ubernerd will not create a symlink on the rootfs of the host.'
fi

echo ''
echo "Enabling IP forwarding..."
echo 1 >/proc/sys/net/ipv4/ip_forward

# Check if the job has failed
if [[ 'failed' == $(systemctl show -p ActiveState --value 'ubernerd-containerd') ]]; then
	# Ensure to reset job if it previously failed (else we can't start it again)
	systemctl reset-failed ubernerd-containerd
fi

echo ''
echo "Starting containerd..."

# Create the transient direcotry under /run (which is tmpfs and not written to disk)
mkdir -p /run/systemd/transient

# Write service file in the location where systemd-run would have created one
# Benefit of not using systemd-run is that we can overwrite/update the service file
# and reload it for changes to take effect (while keeping the same service name)
# When using systemd-run you'd have to make sure the service with same name is fully
# removed using --collect, but this doesn't happen when combined with KillMode=process,
# since the service will continue to exist when sub-processes are still running
# Make containerd use custom directories and pass through all command line arguments
cat <<-EOF >'/run/systemd/transient/ubernerd-containerd.service'
	# Copyright The containerd Authors.
	#
	# Licensed under the Apache License, Version 2.0 (the "License");
	# you may not use this file except in compliance with the License.
	# You may obtain a copy of the License at
	#
	#     http://www.apache.org/licenses/LICENSE-2.0
	#
	# Unless required by applicable law or agreed to in writing, software
	# distributed under the License is distributed on an "AS IS" BASIS,
	# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	# See the License for the specific language governing permissions and
	# limitations under the License.

	[Unit]
	Description=containerd container runtime started by ubernerd
	Documentation=https://containerd.io
	After=network.target local-fs.target

	[Service]
	#uncomment to fallback to legacy CRI plugin implementation with podsandbox support.
	#Environment="DISABLE_CRI_SANDBOXES=1"
	Environment='PATH=$PATH'
	ExecStartPre=-/sbin/modprobe overlay
	ExecStart='$script_parent_dir/nerdctl_full/bin/containerd' \
		--config '${script_parent_dir}/config/containerd/config.toml' \
		--root '${script_parent_dir}/state/containerd/root' \
		--state '${script_parent_dir}/state/containerd/state'

	Type=notify
	Delegate=yes
	KillMode=process
	Restart=always
	RestartSec=5
	# Having non-zero Limit*s causes performance problems due to accounting overhead
	# in the kernel. We recommend using cgroups to do container-local accounting.
	LimitNPROC=infinity
	LimitCORE=infinity
	LimitNOFILE=infinity
	# Comment TasksMax if your systemd version does not supports it.
	# Only systemd 226 and above support this version.
	TasksMax=infinity
	OOMScoreAdjust=-999

	[Install]
	WantedBy=multi-user.target
EOF

# Make systemd realize there's a new/updated service file
systemctl daemon-reload
# Start containerd
systemctl start ubernerd-containerd

echo ''
echo 'Waiting a bit for containerd to start...'

# Execute the command until it is successful
until ./nerdctl info >/dev/null 2>&1; do
	echo -n '.'
	sleep 1
done

echo ''
echo 'Containerd started successfully!'
echo ''
./nerdctl info
