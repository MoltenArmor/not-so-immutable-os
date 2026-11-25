#!/bin/sh
# 导入 mkosi 构建出的所有扩展镜像（ext-*.raw），并让 systemd 重新合并它们。
set -ue

SCRIPT_PATH="$(readlink -nf "$0")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
OUTPUT_PATH="${SCRIPT_DIR}/../mkosi.output"

EXT_DIR="/var/lib/extensions"
CONFEXT_DIR="/var/lib/confexts"

usage() {
    printf '%s\n' 'Usage: update-all-sysexts.sh'
    printf '%s\n' 'Import all ext-*.raw images built by mkosi and merge them.'
}

check_user() {
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s\n' 'Error: This script must be run as root.' >&2
        exit 1
    fi
}

# 用 "$@" 承载 glob 结果，避免未匹配时拿到字面量 "ext-*.raw"。
set -- "${OUTPUT_PATH}"/ext-*.raw
if [ ! -e "$1" ]; then
    printf '%s\n' "No extension images found in ${OUTPUT_PATH}." >&2
    exit 0
fi

check_user

failures=0

for ext_image_path in "$@"; do
    ext_image_basename="$(basename "${ext_image_path}")"

    printf '%s\n' "Importing ${ext_image_basename}..."

    # importctl 不会覆盖已存在的镜像，先移除旧的。
    rm -f "${EXT_DIR}/${ext_image_basename}"

    if ! importctl import-raw "${ext_image_path}" --class=sysext; then
        printf '%s\n' "Error: Failed to import ${ext_image_basename}." >&2
        failures=$((failures + 1))
        continue
    fi

    # 同一份 raw 同时充当 confext。systemd 目前只从 /var/lib/confexts 读取 confext，
    # 而 /var/lib/extensions 尚不能同时保存两者，所以在这里建一个符号链接过去。
    mkdir -p "${CONFEXT_DIR}"
    ln -sf "../extensions/${ext_image_basename}" "${CONFEXT_DIR}/${ext_image_basename}"
done

if [ "${failures}" -ne 0 ]; then
    printf '%s\n' "Error: ${failures} extension image(s) failed to import." >&2
    exit 1
fi

# 合并扩展镜像不会触发 tmpfiles 和 preset，必须手动执行。
# 顺序很重要：先合并（内部会做 daemon-reload），新单元才会被 tmpfiles 和 preset 看见。
if ! systemctl reload-or-restart systemd-sysext.service systemd-confext.service; then
    printf '%s\n' 'Warning: Failed to reload systemd-sysext.service / systemd-confext.service.' >&2
fi

systemd-tmpfiles --create
systemctl preset-all
systemctl --global preset-all

printf '%s\n' 'Import done!'
