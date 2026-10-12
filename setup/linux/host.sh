#!/usr/bin/env bash

# Host facts. Tests fake a host through the HOST_* paths.
: "${HOST_PROC_VERSION:=/proc/version}"
: "${HOST_SYSTEMD_DIR:=/run/systemd/system}"
: "${HOST_OS_RELEASE:=/etc/os-release}"

host_is_wsl() {
  grep -qi microsoft "$HOST_PROC_VERSION" 2> /dev/null
}

host_has_systemd() {
  [[ -d $HOST_SYSTEMD_DIR ]]
}
