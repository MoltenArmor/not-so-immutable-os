#!/bin/sh
# Validate all systemd-userdbd drop-in files under mkosi.images/**/usr/lib/userdb.
set -eu

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"
SEARCH_ROOT="${1:-${REPO_ROOT}/mkosi.images}"

if ! command -v jq >/dev/null 2>&1; then
    printf 'Error: jq is required.\n' >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT INT HUP TERM

UID_MAP="${TMP_DIR}/uids"
GID_MAP="${TMP_DIR}/gids"
USER_MAP="${TMP_DIR}/users"
GROUP_MAP="${TMP_DIR}/groups"
: > "${UID_MAP}"
: > "${GID_MAP}"
: > "${USER_MAP}"
: > "${GROUP_MAP}"

errors=0
checked=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    errors=$((errors + 1))
}

# Two paths under different mkosi.profiles/<name> of the same image are mutually exclusive.
profile_scope() {
    case "$1" in
        */mkosi.profiles/*)
            _base="${1%%/mkosi.profiles/*}"
            _rest="${1#*/mkosi.profiles/}"
            printf '%s\t%s\n' "${_base}" "${_rest%%/*}"
            ;;
        *)
            printf '%s\t\n' "$1"
            ;;
    esac
}

record_and_check_conflict() {
    _map="$1"
    _key="$2"
    _val="$3"
    _file="$4"
    _label="$5"

    _cur_scope="$(profile_scope "${_file}")"
    _cur_base="$(printf '%s' "${_cur_scope}" | cut -f1)"
    _cur_prof="$(printf '%s' "${_cur_scope}" | cut -f2)"

    while IFS="$(printf '\t')" read -r _k _v _f; do
        [ "${_k}" = "${_key}" ] || continue
        _prev_scope="$(profile_scope "${_f}")"
        _prev_base="$(printf '%s' "${_prev_scope}" | cut -f1)"
        _prev_prof="$(printf '%s' "${_prev_scope}" | cut -f2)"

        # Mutually exclusive profiles of the same image may share identical definitions.
        if [ -n "${_cur_prof}" ] && [ -n "${_prev_prof}" ] \
            && [ "${_cur_base}" = "${_prev_base}" ] \
            && [ "${_cur_prof}" != "${_prev_prof}" ]; then
            if [ "${_v}" != "${_val}" ]; then
                fail "${_label} ${_key} differs across sibling profiles: ${_val} (${_file}) vs ${_v} (${_f})"
            fi
            continue
        fi

        fail "${_label} conflict on ${_key}: ${_val} (${_file}) vs ${_v} (${_f})"
    done < "${_map}"

    printf '%s\t%s\t%s\n' "${_key}" "${_val}" "${_file}" >> "${_map}"
}

DIRS_LIST="${TMP_DIR}/dirs"
find "${SEARCH_ROOT}" -type d -path '*/usr/lib/userdb' | sort > "${DIRS_LIST}"

while IFS= read -r dir; do
    [ -n "${dir}" ] || continue

    for path in "${dir}"/*; do
        [ -e "${path}" ] || [ -L "${path}" ] || continue
        name="$(basename -- "${path}")"
        checked=$((checked + 1))

        case "${name}" in
            [0-9]*.user)
                num="${name%.user}"
                case "${num}" in *[!0-9]*|'') fail "Invalid numeric user filename: ${path}"; continue ;; esac
                if [ ! -L "${path}" ]; then
                    fail "Numeric user record must be a symlink: ${path}"
                    continue
                fi
                target="$(readlink "${path}")"
                case "${target}" in
                    */*) fail "Symlink target must be relative in same dir: ${path} -> ${target}"; continue ;;
                    *.user) ;;
                    *) fail "Symlink target must end with .user: ${path} -> ${target}"; continue ;;
                esac
                if [ ! -f "${dir}/${target}" ]; then
                    fail "Broken symlink: ${path} -> ${target}"
                    continue
                fi
                uid="$(jq -r 'if (.uid | type) == "number" then .uid else "" end' "${dir}/${target}" 2>/dev/null || true)"
                if [ "${uid}" != "${num}" ]; then
                    fail "Symlink UID mismatch: ${path} -> ${target} (uid=${uid})"
                fi
                ;;

            [0-9]*.group)
                num="${name%.group}"
                case "${num}" in *[!0-9]*|'') fail "Invalid numeric group filename: ${path}"; continue ;; esac
                if [ ! -L "${path}" ]; then
                    fail "Numeric group record must be a symlink: ${path}"
                    continue
                fi
                target="$(readlink "${path}")"
                case "${target}" in
                    */*) fail "Symlink target must be relative in same dir: ${path} -> ${target}"; continue ;;
                    *.group) ;;
                    *) fail "Symlink target must end with .group: ${path} -> ${target}"; continue ;;
                esac
                if [ ! -f "${dir}/${target}" ]; then
                    fail "Broken symlink: ${path} -> ${target}"
                    continue
                fi
                gid="$(jq -r 'if (.gid | type) == "number" then .gid else "" end' "${dir}/${target}" 2>/dev/null || true)"
                if [ "${gid}" != "${num}" ]; then
                    fail "Symlink GID mismatch: ${path} -> ${target} (gid=${gid})"
                fi
                ;;

            *.user)
                [ ! -L "${path}" ] || { fail "Named user record should be a regular file: ${path}"; continue; }
                stem="${name%.user}"
                if ! jq -e 'type == "object"' "${path}" >/dev/null 2>&1; then
                    fail "Invalid JSON object: ${path}"
                    continue
                fi
                uname="$(jq -r 'if (.userName | type) == "string" then .userName else "" end' "${path}")"
                uid="$(jq -r 'if (.uid | type) == "number" and (.uid == (.uid | floor)) and .uid >= 0 then .uid else "" end' "${path}")"
                gid="$(jq -r 'if (.gid | type) == "number" and (.gid == (.gid | floor)) and .gid >= 0 then .gid else "" end' "${path}")"
                if [ "${uname}" != "${stem}" ]; then
                    fail "userName mismatch in ${path}: expected '${stem}', got '${uname}'"
                    continue
                fi
                if [ -z "${uid}" ] || [ -z "${gid}" ]; then
                    fail "Missing or invalid integer uid/gid in ${path}"
                    continue
                fi
                if [ ! -L "${dir}/${uid}.user" ]; then
                    fail "Missing UID symlink ${dir}/${uid}.user for ${path}"
                elif [ "$(readlink "${dir}/${uid}.user")" != "${name}" ]; then
                    fail "UID symlink ${dir}/${uid}.user points to '$(readlink "${dir}/${uid}.user")', expected '${name}'"
                fi
                record_and_check_conflict "${UID_MAP}" "${uid}" "${uname}" "${path}" "UID"
                record_and_check_conflict "${USER_MAP}" "${uname}" "${uid}" "${path}" "userName"
                ;;

            *.group)
                [ ! -L "${path}" ] || { fail "Named group record should be a regular file: ${path}"; continue; }
                stem="${name%.group}"
                if ! jq -e 'type == "object"' "${path}" >/dev/null 2>&1; then
                    fail "Invalid JSON object: ${path}"
                    continue
                fi
                gname="$(jq -r 'if (.groupName | type) == "string" then .groupName else "" end' "${path}")"
                gid="$(jq -r 'if (.gid | type) == "number" and (.gid == (.gid | floor)) and .gid >= 0 then .gid else "" end' "${path}")"
                if [ "${gname}" != "${stem}" ]; then
                    fail "groupName mismatch in ${path}: expected '${stem}', got '${gname}'"
                    continue
                fi
                if [ -z "${gid}" ]; then
                    fail "Missing or invalid integer gid in ${path}"
                    continue
                fi
                if [ ! -L "${dir}/${gid}.group" ]; then
                    fail "Missing GID symlink ${dir}/${gid}.group for ${path}"
                elif [ "$(readlink "${dir}/${gid}.group")" != "${name}" ]; then
                    fail "GID symlink ${dir}/${gid}.group points to '$(readlink "${dir}/${gid}.group")', expected '${name}'"
                fi
                record_and_check_conflict "${GID_MAP}" "${gid}" "${gname}" "${path}" "GID"
                record_and_check_conflict "${GROUP_MAP}" "${gname}" "${gid}" "${path}" "groupName"
                ;;

            *:*.membership)
                [ ! -L "${path}" ] || { fail "Membership record should be a regular file: ${path}"; continue; }
                stem="${name%.membership}"
                muser="${stem%%:*}"
                mgroup="${stem#*:}"
                if [ -z "${muser}" ] || [ -z "${mgroup}" ] || [ "${muser}:${mgroup}" != "${stem}" ]; then
                    fail "Invalid membership filename: ${path}"
                    continue
                fi
                if ! jq -e 'type == "object"' "${path}" >/dev/null 2>&1; then
                    fail "Invalid JSON object: ${path}"
                fi
                ;;

            *)
                fail "Unexpected file in userdb directory: ${path}"
                ;;
        esac
    done
done < "${DIRS_LIST}"

if [ "${errors}" -ne 0 ]; then
    printf 'userdb check failed with %d error(s) (%d entries checked).\n' "${errors}" "${checked}" >&2
    exit 1
fi

printf 'OK: %d userdb entries checked, 0 errors.\n' "${checked}"
