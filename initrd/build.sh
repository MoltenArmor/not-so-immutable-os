#!/bin/sh -ue

VTOYBOOT='https://github.com/MoltenArmor/vtoyboot/releases/download/1.0/vtoyboot.tar.gz'
TMPDIR="$(mktemp -d)"

clean() {
    rm -rf "${TMPDIR}"
}

trap clean EXIT

[ ! -d mkosi.extra/root/vtoyboot ] && \
    mkdir -p mkosi.extra/root && \
    curl -sSL "${VTOYBOOT}" -o "${TMPDIR}/vtoyboot.tar.gz" && \
    tar -xvf "${TMPDIR}/vtoyboot.tar.gz" -C mkosi.extra/root/

mkosi build

rm -rf mkosi.output/tmp
