#!/bin/sh
set -ue

BASE_DIR="/run/tmpify"

cleanup_on_interrupt() {
    if [ -n "${TMPIFY_UPPER:-}" ] && [ -n "${TMPIFY_WORK:-}" ]; then
        rm -rf "${TMPIFY_UPPER}" || :
        rm -rf "${TMPIFY_WORK}" || :
    fi
}

trap cleanup_on_interrupt INT TERM

usage() {
    printf '%s\n' "Make a directory ephemeral by mounting an overlay tmpfs."
    printf '%s\n' "Usage:"
    printf '%s\n' "  $0 <directory>      Tmpify a directory."
    printf '%s\n' "  $0 -r|--restore <directory>   Restore a directory."
}

safe_path() {
    printf '%s' "$1" | tr -s '/' '_'
}

check_user() {
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s\n' "Error: This script must be run as root." >&2
        exit 1
    fi
}

do_mount() {
    target_dir="$(readlink -nf "$1")"

    if [ -z "${target_dir}" ]; then
        printf '%s\n' "Error: Invalid path." >&2
        exit 1
    fi

    if [ ! -d "${target_dir}" ]; then
        printf '%s\n' "Error: Not a directory!" >&2
        exit 1
    fi

    if findmnt -t overlay -T "${target_dir}" > /dev/null 2>&1; then
        printf '%s\n' "Error: ${target_dir} is already an overlay mountpoint." >&2
        exit 1
    fi

    mkdir -p "${BASE_DIR}"

    upper_dir="${BASE_DIR}/upper$(safe_path "${target_dir}")"
    work_dir="${BASE_DIR}/work$(safe_path "${target_dir}")"
    
    # Set trap variables before creating directories
    TMPIFY_UPPER="${upper_dir}"
    TMPIFY_WORK="${work_dir}"
    
    mkdir -p "${upper_dir}" "${work_dir}"

    if ! mount -t overlay overlay \
        -o lowerdir="${target_dir}",upperdir="${upper_dir}",workdir="${work_dir}" \
        "${target_dir}"; then
        printf '%s\n' "Error: Failed to mount overlay." >&2
        rm -rf "${upper_dir}" || :
        rm -rf "${work_dir}" || :
        TMPIFY_UPPER=
        TMPIFY_WORK=
        exit 1
    fi
    
    # Clear trap variables after successful mount
    TMPIFY_UPPER=
    TMPIFY_WORK=

    printf '%s\n' "Successfully tmpified ${target_dir}"
    printf '%s\n' "To revert, run $0 -r|--restore ${target_dir}"
}

do_unmount() {
    target_dir="$(readlink -nf "$1")"

    if [ -z "${target_dir}" ]; then
        printf '%s\n' "Error: Invalid path." >&2
        exit 1
    fi

    if ! umount "${target_dir}" 2>/dev/null && ! umount -l "${target_dir}" 2>/dev/null; then
        printf '%s\n' "Error: Failed to umount ${target_dir}" >&2
        exit 1
    fi

    rm -rf "${BASE_DIR}/upper$(safe_path "${target_dir}")" || :
    rm -rf "${BASE_DIR}/work$(safe_path "${target_dir}")" || :

    printf '%s\n' "Successfully restored ${target_dir}"
}

RESTORE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        '-r' | '--restore')
            RESTORE=1
            shift
            ;;
        '-h' | '--help')
            usage
            exit 0
            ;;
        '--')
            shift
            break
            ;;
        -*)
            printf '%s\n' "Unknown option: $1" >&2
            usage
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [ "$#" -eq 0 ]; then
    usage
    exit 0
fi

check_user

TARGET_DIR="${1:-}"

if [ "${RESTORE}" -eq 1 ]; then
    do_unmount "${TARGET_DIR}"
else
    do_mount "${TARGET_DIR}"
fi

exit 0
