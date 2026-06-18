#!/usr/bin/env bash

# Central defaults for prepare_docker shell scripts.
# Override via environment variables or by creating prepare_docker/config.local.sh.

NAMESPACE_DEFAULT="wl"
KC_CMD_DEFAULT="kc"

MK_PRF_DEFAULT="wlcluster"
MK_NODES_DEFAULT="3"

PV_PATH_DEFAULT="/mnt/weblogic/pv-home"
WLS_IMAGE_TAG_DEFAULT="wls-dev:1.3"

PUBKEY_DEFAULT="${HOME}/.ssh/id_ed25519_docker.pub"
PRIVKEY_DEFAULT="${HOME}/.ssh/id_ed25519_docker"

AUTO_YES_DEFAULT="0"

