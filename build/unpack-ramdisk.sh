#!/usr/bin/env bash

set -e -u

SCRIPT_DIR=$(dirname "$(realpath "$0")")
export PATH="${SCRIPT_DIR}/bin:${PATH}"

print_usage() {
	local script_name
	script_name=$(basename "$0")

	echo
	echo "Usage: ${script_name} [ramdisk] [output directory]"
	echo
	echo "Helper script for unpacking ramdisk."
	echo
}

if [ $# -lt 2 ]; then
	echo
	echo "Missing some arguments."
	print_usage
	exit 1
fi

INPUT_RAMDISK="$1"
OUTPUT_DIRECTORY="$2"

if [ -z "$(command -v cpio)" ]; then
	echo "Utility 'cpio' is not found in PATH."
	exit 1
fi

if [ -z "$(command -v xzcat)" ]; then
	echo "Utility 'xzcat' is not found in PATH."
	exit 1
fi

if [ -e "$OUTPUT_DIRECTORY" ]; then
	echo "Output directory '${OUTPUT_DIRECTORY}' already exist."
	exit 1
fi

if [ ! -e "$INPUT_RAMDISK" ]; then
	echo "Ramdisk file '${INPUT_RAMDISK}' is not found."
	exit 1
else
	INPUT_RAMDISK=$(realpath "$INPUT_RAMDISK")
fi

umask 0022
mkdir "$OUTPUT_DIRECTORY"
cd "$OUTPUT_DIRECTORY"
xzcat "$INPUT_RAMDISK" | cpio -i
