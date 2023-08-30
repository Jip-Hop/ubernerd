#!/usr/bin/env bash

set -euo pipefail

# Set the CREATE_SYMLINK environment variable to 1 to make the nerdctl command available globally
# This will modify the host rootfs
CREATE_SYMLINK="${CREATE_SYMLINK:-0}"

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

# TODO: should be possible to start containerd without systemd...
is_executable_available 'systemctl' || fail "systemctl is required but not available..."

# Check if ubernerd-containerd is already running, else don't continue and tell user to manually stop it first
if systemctl is-active --quiet "ubernerd-containerd"; then
	echo 'Abort: ubernerd-containerd is already running!'
	echo 'You may stop it with: systemctl stop ubernerd-containerd.'
	fail 'Be aware that this will stop all running containers!'
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
		wget -qO- "$url"
	elif is_executable_available 'curl'; then
		curl -sSL "$url"
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

# Check if containerd and nerdctl inside nerdctl_full, else download and extract latest release
# TODO: Update/upgrade logic: currently ubernerd only installs latest version once, and sticks to that version

if [[ -f 'nerdctl_full/bin/containerd' && -f 'nerdctl_full/bin/nerdctl' ]]; then
	echo ''
	echo 'Found containerd and nerdctl inside nerdctl_full directory (no need to download).'
else
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

	download_url="$(download 'https://api.github.com/repos/containerd/nerdctl/releases/latest' | mygrep 'nerdctl-full-' | mygrep "-linux-$arch.tar.gz" | mygrep 'browser_download_url' | cut -d '"' -f 4)"

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

# TODO: build this script string in a different way,
# so I don't have to escape inside the string,
# and I can have proper syntax checking

nerdctl_script_contents=$(
	cat <<EOF
#!/usr/bin/env bash

export PATH="$PATH"

# Make nerdctl use our config file
export NERDCTL_TOML="${script_parent_dir}/config/nerdctl/nerdctl.toml"

# Make nerdctl use custom directories and pass through all command line arguments
nerdctl --data-root "${script_parent_dir}/state/nerdctl/data_root" --cni-path "${script_parent_dir}/nerdctl_full/libexec/cni" --cni-netconfpath "${script_parent_dir}/config/cni/net.d" "\$@"
EOF
)

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

# Unset trap, no need to know line numbers from here on
trap - ERR

# Make containerd use custom directories and pass through all command line arguments
# Use KillMode=mixed instead of KillMode=process to also kill subprocesses (including all running containers),
# otherwise there's no way to shutdown ubernerd and run this script again

# TODO: perhaps I can use KillMode=process when I stop using systemd-run and instead write a .service file directly
# to /run/systemd/transient/
# That seems to be what systemd-run does under the hood
# But then I should be able to overwrite this .service file and allow it to be reloaded and restarted...
# Which systemd-run doesn't allow me to do if there are still sub-processes running...
systemd-run \
	--unit='ubernerd-containerd' \
	--description='containerd container runtime started by ubernerd' \
	--collect \
	-p Delegate=yes \
	-p KillMode=mixed \
	-p LimitNPROC=infinity \
	-p LimitCORE=infinity \
	-p LimitNOFILE=infinity \
	-p TasksMax=infinity \
	-p OOMScoreAdjust=-999 \
	--setenv=PATH \
	-- \
	containerd \
	--config "${script_parent_dir}/config/containerd/config.toml" \
	--root "${script_parent_dir}/state/containerd/root" \
	--state "${script_parent_dir}/state/containerd/state"

echo ''
echo 'Waiting a bit for containerd to start...'
sleep 2

echo ''
SYSTEMD_COLORS=1 journalctl -u ubernerd-containerd -e | tail -n 5
