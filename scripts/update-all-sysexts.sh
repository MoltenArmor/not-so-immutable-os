#!/bin/sh
set -ue

SCRIPT_PATH="$(readlink -nf "$0")"
OUTPUT_PATH="${SCRIPT_PATH}/../mkosi.output"

for sysext_image_path in "${OUTPUT_PATH}"/sysext-*; do
    sysext_image_basename="$(basename "${sysext_image_path}")"
    if [ -f "/var/lib/extensions/${sysext_image_basename}" ]; then
        rm -f "/var/lib/extensions/${sysext_image_basename}"
    fi
    importctl import-raw "${sysext_image_path}" --class=sysext
done

printf '%s\n' 'Import done! Please execute "systemctl reload systemd-sysext.service"!'
