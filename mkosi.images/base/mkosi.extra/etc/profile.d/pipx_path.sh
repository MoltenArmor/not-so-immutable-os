#!/bin/sh
PIPX_GLOBAL_HOME="/var/opt/pipx"
PIPX_GLOBAL_BIN_DIR="/var/opt/pipx/bin"
PIPX_GLOBAL_MAN_DIR="/var/opt/pipx/man"
export PIPX_GLOBAL_HOME
export PIPX_GLOBAL_BIN_DIR
export PIPX_GLOBAL_MAN_DIR
PATH="$PATH:$PIPX_GLOBAL_BIN_DIR"
