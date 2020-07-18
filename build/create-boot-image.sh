#!/usr/bin/env bash

set -e -u

BOOTIMG_PAGE_SIZE="2048"
BOOTIMG_BASE="0x10000000"
BOOTIMG_KERNEL_OFFSET="0x00008000"
BOOTIMG_RAMDISK_OFFSET="0x01000000"
BOOTIMG_SECOND_OFFSET="0x00f00000"
BOOTIMG_TAGS_OFFSET="0x00000100"
BOOTIMG_KERNEL_CMDLINE="buildvariant=userdebug"
BOOTIMG_HASH="sha1"
BOOTIMG_OS_VERSION="9.0.0"
BOOTIMG_OS_PATCH_LEVEL="2019-06"

SCRIPT_DIR=$(dirname "$(realpath "$0")")
export PATH="${SCRIPT_DIR}/bin:${PATH}"

print_usage() {
	local script_name
	script_name=$(basename "$0")

	echo
	echo "Usage: ${script_name} [output file] [Image|zImage] [ramdisk] [dt]"
	echo
	echo "Helper script for generating boot.img."
	echo
}

if [ $# -lt 4 ]; then
	echo
	echo "Missing some arguments."
	print_usage
	exit 1
fi

OUTPUT_FILE="$1"
INPUT_KERNEL_IMAGE="$2"
INPUT_RAMDISK="$3"
INPUT_DT="$4"

if [ -z "$(command -v mkbootimg)" ]; then
	echo "Utility 'mkbootimg' is not found in PATH."
	exit 1
fi

if [ -e "${OUTPUT_FILE}" ]; then
	echo "Refusing to overwrite existing file '$OUTPUT_FILE'."
	exit 1
fi

for input_file in "$INPUT_KERNEL_IMAGE" "$INPUT_RAMDISK" "$INPUT_DT"; do
	if [ ! -e "$input_file" ]; then
		echo "Input file '${input_file}' is not found."
		exit 1
	fi
done
unset input_file

exec mkbootimg --kernel "$INPUT_KERNEL_IMAGE" --ramdisk "$INPUT_RAMDISK" \
	--dt "$INPUT_DT" --cmdline "$BOOTIMG_KERNEL_CMDLINE" --base "$BOOTIMG_BASE" \
	--pagesize "$BOOTIMG_PAGE_SIZE" --kernel_offset "$BOOTIMG_KERNEL_OFFSET" \
	--ramdisk_offset "$BOOTIMG_RAMDISK_OFFSET" --second_offset "$BOOTIMG_SECOND_OFFSET" \
	--tags_offset "$BOOTIMG_TAGS_OFFSET" --os_version "$BOOTIMG_OS_VERSION" \
	--os_patch_level "$BOOTIMG_OS_PATCH_LEVEL" --hash "$BOOTIMG_HASH" \
	--output "$OUTPUT_FILE"
