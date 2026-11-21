#!/bin/sh
# Download a source archive and extract it straight into DEST, without the top-level directory.
# tar detects the compression (gzip, bzip2 or xz) itself.
# The archive is removed on exit, also when a step fails.
# Usage: fetch-src URL ARCHIVE DEST
set -e
trap 'rm -f "$2"' EXIT
wget -q "$1" -O "$2"
mkdir -p "$3"
tar -xf "$2" -C "$3" --strip-components=1
