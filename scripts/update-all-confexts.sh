#!/bin/sh
set -ue

SCRIPT_PATH="$(readlink -nf "$0")"
OUTPUT_PATH="${SCRIPT_PATH}/../mkosi.output"

for confext_image_path in "${OUTPUT_PATH}"/confext-*; do
    confext_image_basename="$(basename "${confext_image_path}")"
    if [ -f "/var/lib/extensions/${confext_image_basename}" ]; then
        rm -f "/var/lib/extensions/${confext_image_basename}"
    fi
    importctl import-raw "${confext_image_path}" --class=confext
done

printf '%s\n' 'Import done! Please execute "systemctl reload systemd-confext.service"!'
