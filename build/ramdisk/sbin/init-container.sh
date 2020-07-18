#!/sbin/busybox ash
##
##  Initialize and start RunC container.
##  Container is located in tmpfs and therefore not persistent.
##

set -e -u

## Redirect output to kmsg.
exec > /dev/kmsg
exec 2>&1

## Rely only on busybox applets.
unset PATH

## Wait 30 sec before start.
sleep 30

## Container name.
CONTAINER_NAME="android-runc-container"

## RunC base directory.
RUNC_BASE_DIR="/mnt/runc"

## Path to directory where RunC will store container state.
RUNC_RUNTIME_DIR="${RUNC_BASE_DIR}/runtime"

## Directory where container will be stored (this should not be changed).
CONTAINER_DIR="${RUNC_BASE_DIR}/container"

## Directory where rootfs will be stored (this should not be changed).
CONTAINER_ROOTFS_DIR="${CONTAINER_DIR}/rootfs"

## Path to configuration files.
CONTAINER_STATIC_FILES_DIR="/res/runc"

## Archive with root file system content.
CONTAINER_ROOTFS_ARCHIVE="${CONTAINER_STATIC_FILES_DIR}/alpine-linux-rootfs.tar"

## Size of the rootfs device in MiB.
ZRAM_DISK_SIZE="1024"

## Create a directory at specified path. If path exists but is not a directory,
## it will be deleted. Ownership and permissions are set regardless of was
## directory created now or not.
##
## Usage: create_dir [path] [ownership] [permissions]
##
create_dir() {
	## Remove path if it exists but not a directory.
	if [ -e "${1}" ] && [ ! -d "${1}" ]; then
		echo -n "[*] RunC: path '${1}' exists but not a directory, deleting... "
		if rm -rf "${1}" > /dev/null 2>&1; then
			echo "ok"
		else
			echo "fail"
			return 1
		fi
	fi

	## Create directory at path if it does not exist.
	if [ ! -e "${1}" ]; then
		echo -n "[*] RunC: creating directory '${1}'... "
		if mkdir -p "${1}" > /dev/null 2>&1; then
			echo "ok"
		else
			echo "fail"
			return 1
		fi
	fi

	## Set ownership.
	## Note that ours busybox is compiled against Musl-libc and since
	## on Android file /etc/passwd usually does not exist, we have to
	## use numeric IDs instead of names for 'chown'.
	echo -n "[*] RunC: setting ownership to '${2}' for directory '${1}'... "
	if chown "${2}" "${1}" > /dev/null 2>&1; then
		echo "ok"
	else
		echo "fail"
		return 1
	fi

	## Set permissions.
	echo -n "[*] RunC: setting permissions to '${3}' for directory '${1}'... "
	if chmod "${3}" "${1}" > /dev/null 2>&1; then
		echo "ok"
	else
		echo "fail"
		return 1
	fi
}

## Copy file from source to destination. If file exists at destination path,
## it will not be overwritten unless it is a directory or has special type.
## Specified ownership and permissions will be set regardless of was file
## created (copied) now or not.
##
## Usage: copy_file [source] [destination] [ownership] [permissions]
##
copy_file() {
	if [ ! -e "${1}" ]; then
		echo "[!] RunC: cannot copy non-existent file '${1}'."
		return 1
	fi

	if [ ! -f "${1}" ]; then
		echo "[!] RunC: cannot copy non-regular file '${1}'."
		return 1
	fi

	## Remove destination path if it exists but not a file.
	if [ -e "${2}" ] && [ ! -f "${2}" ]; then
		echo -n "[*] RunC: path '${2}' exists but not a regular file, deleting... "
		if rm -rf "${2}" > /dev/null 2>&1; then
			echo "ok"
		else
			echo "fail"
			return 1
		fi
	fi

	## Copy file to specified destination.
	if [ ! -e "${2}" ]; then
		echo -n "[*] RunC: copying file '${1}' to '${2}'... "
		if cp "${1}" "${2}" > /dev/null 2>&1; then
			echo "ok"
		else
			echo "fail"
			return 1
		fi
	fi

	## Set ownership.
	echo -n "[*] RunC: setting ownership to '${3}' for file '${2}'... "
	if chown "${3}" "${2}" > /dev/null 2>&1; then
		echo "ok"
	else
		echo "fail"
		return 1
	fi

	## Set permissions.
	echo -n "[*] RunC: setting permissions to '${4}' for file '${2}'... "
	if chmod "${4}" "${2}" > /dev/null 2>&1; then
		echo "ok"
	else
		echo "fail"
		return 1
	fi
}

## Setup basic container directories.
create_dir "${RUNC_BASE_DIR}" "0:0" "700"
if ! mountpoint -q "${RUNC_BASE_DIR}"; then
	## Setting up zRam disk where everything will be placed.
	echo -n "[*] RunC: setting zRam disk compression to LZO... "
	if echo "1" > /sys/block/zram0/reset 2>/dev/null && echo "lzo" > /sys/block/zram0/comp_algorithm 2>/dev/null; then
		echo "ok"
	else
		echo "fail"
		exit 1
	fi
	echo -n "[*] RunC: setting zRam disk size to ${ZRAM_DISK_SIZE}M... "
	if echo $((1048576 * ZRAM_DISK_SIZE)) > /sys/block/zram0/disksize 2>/dev/null; then
		echo "ok"
	else
		echo "fail"
		exit 1
	fi
	echo -n "[*] RunC: formatting zRam disk to EXT2... "
	if mke2fs -m 3 -L RUNC_CONTAINER /dev/block/zram0 > /dev/null 2>&1; then
		echo "ok"
	else
		echo "fail"
		exit 1
	fi

	## Mounting zRam disk to RunC base directory.
	echo -n "[*] RunC: mounting zRam disk to RunC directory... "
	if mount -t ext4 -o rw,relatime /dev/block/zram0 "${RUNC_BASE_DIR}" > /dev/null 2>&1; then
		echo "ok"
	else
		echo "fail"
		exit 1
	fi
fi

create_dir "${RUNC_RUNTIME_DIR}" "0:0" "700"
create_dir "${CONTAINER_DIR}" "0:0" "755"
create_dir "${CONTAINER_ROOTFS_DIR}" "0:0" "755"
copy_file "${CONTAINER_STATIC_FILES_DIR}/config.json" "${CONTAINER_DIR}/config.json" "0:0" "600"

## Needed in case if runc was killed and needs restart.
if [ -z "$(pgrep -f "/sbin/runc .+ android-runc-container")" ]; then
	rm -rf "${RUNC_RUNTIME_DIR}/${CONTAINER_NAME}" > /dev/null 2>&1
fi

## Setup rootfs.
if [ -z "$(find "${CONTAINER_ROOTFS_DIR}" -mindepth 1 -maxdepth 1 -quit)" ]; then
	echo -n "[*] Extracting Alpine Linux rootfs... "
	if tar xf "${CONTAINER_ROOTFS_ARCHIVE}" -C "${CONTAINER_ROOTFS_DIR}" > /dev/null 2>&1; then
		echo "ok"
	else
		echo "fail"
		exit 1
	fi
fi

echo "[*] RunC: launching container..."
exec /sbin/runc --root "${RUNC_RUNTIME_DIR}" \
	run --no-pivot --bundle "${CONTAINER_DIR}" "${CONTAINER_NAME}"
