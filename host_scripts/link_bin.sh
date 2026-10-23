#!/bin/bash
# Symlink the host-side scripts into a bin directory on your PATH, under the
# short command names used throughout this repo's docs.
#
# Usage:
#   link_bin.sh            # create/refresh links in ~/.tools/bin
#   link_bin.sh -r         # remove the links this script manages
#   BIN_DIR=~/bin link_bin.sh
#
# Commands created:
#   usb_connect_port -> host_scripts/connect.sh           iproxy tunnel to the device
#   ios_decrypt      -> host_scripts/decrypt_and_pull.sh  decrypt installed apps to .ipa
#   td_pull          -> host_scripts/pull_from_device.sh  grab TrollDecrypt output
#   ts_install       -> host_scripts/ts_install.sh        install an .ipa via TrollStore
#   proxy2phone      -> host_scripts/proxy.sh             tunnel the HTTP proxy to the device
#   frida_connect    -> host_scripts/frida_connect.sh     frida-ps -U
#   frida-dump       -> frida/ios-dump/dump.py            the underlying dumper
#   syscall          -> rev_eng/syscall.sh                Darwin syscall lookup by name/number
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.tools/bin}"

LINKS=(
    "usb_connect_port:host_scripts/connect.sh"
    "ios_decrypt:host_scripts/decrypt_and_pull.sh"
    "td_pull:host_scripts/pull_from_device.sh"
    "ts_install:host_scripts/ts_install.sh"
    "proxy2phone:host_scripts/proxy.sh"
    "frida_connect:host_scripts/frida_connect.sh"
    "frida-dump:frida/ios-dump/dump.py"
    "syscall:rev_eng/syscall.sh"
)

REMOVE=0
case "${1:-}" in
    -r|--remove) REMOVE=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    "") ;;
    *) echo "!! unknown option: $1"; exit 2 ;;
esac

if [ "$REMOVE" -eq 1 ]; then
    for entry in "${LINKS[@]}"; do
        name="${entry%%:*}"; link="$BIN_DIR/$name"
        if [ -L "$link" ]; then rm "$link"; echo ">> removed $link"; fi
    done
    exit 0
fi

mkdir -p "$BIN_DIR"
for entry in "${LINKS[@]}"; do
    name="${entry%%:*}"; rel="${entry#*:}"; target="$REPO_ROOT/$rel"; link="$BIN_DIR/$name"
    if [ ! -f "$target" ]; then echo "!! missing target: $target"; continue; fi
    chmod +x "$target"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        echo "!! $link exists and is not a symlink; leaving it alone"; continue
    fi
    ln -sfn "$target" "$link"
    printf ">> %-18s -> %s\n" "$name" "$rel"
done

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo; echo ">> $BIN_DIR is not on your PATH. Add to your shell rc:"; echo "   export PATH=\"\$PATH:$BIN_DIR\"" ;;
esac
