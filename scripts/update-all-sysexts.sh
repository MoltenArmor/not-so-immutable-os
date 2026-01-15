#!/bin/sh
set -ue

SCRIPT_PATH="$(readlink -nf "$0")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
OUTPUT_PATH="${SCRIPT_DIR}/../mkosi.output"

for ext_image_path in "${OUTPUT_PATH}"/ext-*.raw; do
    ext_image_basename="$(basename "${ext_image_path}")"
    if [ -f "/var/lib/extensions/${ext_image_basename}" ]; then
        rm -f "/var/lib/extensions/${ext_image_basename}"
    fi
    importctl import-raw "${ext_image_path}" --class=sysext

    ln -s "../extensions/${ext_image_basename}" "/var/lib/confexts/${ext_image_basename}"
done

printf '%s\n' "Import done! Please execute 'systemctl reload systemd-sysext.service systemd-confext.service'!"
