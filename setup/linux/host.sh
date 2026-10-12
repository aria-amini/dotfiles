#!/usr/bin/env bash

# Host facts. Tests fake a host through HOST_PROC_VERSION and HOST_SYSTEMD_DIR.
: "${HOST_PROC_VERSION:=/proc/version}"
: "${HOST_SYSTEMD_DIR:=/run/systemd/system}"

host_is_wsl() {
  grep -qi microsoft "$HOST_PROC_VERSION" 2> /dev/null
}

host_has_systemd() {
  [[ -d $HOST_SYSTEMD_DIR ]]
}
