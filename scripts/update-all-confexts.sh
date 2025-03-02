#!/bin/sh
set -ue

SCRIPT_PATH="$(readlink -nf "$0")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
OUTPUT_PATH="${SCRIPT_DIR}/../mkosi.output"

for confext_image_path in "${OUTPUT_PATH}"/confext-*.raw; do
    confext_image_basename="$(basename "${confext_image_path}")"
    if [ -f "/var/lib/confexts/${confext_image_basename}" ]; then
        rm -f "/var/lib/confexts/${confext_image_basename}"
    fi
    importctl import-raw "${confext_image_path}" --class=confext
done

printf '%s\n' 'Import done! Please execute "systemctl reload systemd-confext.service"!'
