#!/bin/bash
#
# syscall - a "man page" for Darwin / Apple-platform syscalls.
#
# Looks up syscalls by name OR number against the SDK headers Xcode ships:
#   - sys/syscall.h   -> name <-> number table (every platform)
#   - sys/sysproto.h  -> argument structs + kernel prototypes (macOS SDK)
#   - man 2 <name>    -> a short description, when a userland man page exists
#
# Usage:
#   syscall <platform> <name|number>   lookup a syscall
#   syscall <name|number>              lookup, defaulting platform to macosx
#   syscall -l                         list available platforms
#   syscall -r                         rebuild the header-path cache, then exit
#   syscall -h                         this help
#
# Examples:
#   syscall iphone write      # iPhoneOS, by name
#   syscall macosx 4          # macOS, by number -> SYS_write
#   syscall mmap              # defaults to macosx
#
# Platform match is case-insensitive and substring-based, so "iphone",
# "iPhoneOS", "tv", "watch", "xr", "mac" all work.
#
# The expensive part is walking Xcode's Platforms/ tree, so the resolved
# header paths are cached under ${XDG_CACHE_HOME:-~/.cache}/syscall and reused
# until the Developer dir changes (or you pass -r). First run is slow; the
# rest are instant.

set -euo pipefail

DEFAULT_PLATFORM="macosx"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/syscall"
CACHE_HEADERS="$CACHE_DIR/headers"
CACHE_SYSPROTO="$CACHE_DIR/sysproto"
CACHE_DEV="$CACHE_DIR/dev"

usage() {
    # Print the comment header (skip the shebang, stop at the first code line).
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit "${1:-0}"
}

# --- locate the Developer dir (don't trust a hardcoded path) ---
find_developer_dir() {
    local candidates=(
        "/Applications/Dev/Xcode.app/Contents/Developer"
        "$(xcode-select -p 2>/dev/null || true)"
        "$(xcrun --show-sdk-path 2>/dev/null | sed 's#/Platforms/.*##' || true)"
    )
    for d in "${candidates[@]}"; do
        [ -n "$d" ] && [ -d "$d/Platforms" ] && { echo "$d"; return 0; }
    done
    echo "error: could not find an Xcode Developer dir with a Platforms/ folder" >&2
    echo "       set it manually: export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer" >&2
    exit 1
}

DEV="${DEVELOPER_DIR:-$(find_developer_dir)}"

# --- cache: walk Platforms/ once, then read resolved paths from disk ---
# The two finds below are the only slow thing in this script. Run them lazily,
# once, and only re-run when the Developer dir changes or -r forces it.
build_cache() {
    mkdir -p "$CACHE_DIR"
    # All non-simulator name<->number tables. Prefer the clean usr/include copy
    # over the Kernel.framework one.
    find "$DEV/Platforms" -name "syscall.h" -path "*/sys/syscall.h" 2>/dev/null \
        | grep -iv "simulator" \
        | grep -iv "Kernel.framework" > "$CACHE_HEADERS.tmp" || true
    mv "$CACHE_HEADERS.tmp" "$CACHE_HEADERS"
    # sysproto.h lives in the macOS Kernel framework; it's the arg-struct source.
    find "$DEV/Platforms" -name "sysproto.h" -path "*Kernel.framework*" 2>/dev/null \
        | head -1 > "$CACHE_SYSPROTO.tmp" || true
    mv "$CACHE_SYSPROTO.tmp" "$CACHE_SYSPROTO"
    printf '%s\n' "$DEV" > "$CACHE_DEV"
}

ensure_cache() {
    if [ "${1:-}" != "force" ] \
        && [ -f "$CACHE_DEV" ] && [ -f "$CACHE_HEADERS" ] && [ -f "$CACHE_SYSPROTO" ] \
        && [ "$(cat "$CACHE_DEV" 2>/dev/null)" = "$DEV" ]; then
        return 0
    fi
    build_cache
}

list_syscall_headers() { cat "$CACHE_HEADERS"; }
find_sysproto()        { cat "$CACHE_SYSPROTO"; }

list_platforms() {
    echo "Available platforms:"
    list_syscall_headers | sed -E 's#.*/Platforms/([^/]+)\.platform/.*#  \1#' | sort -u
}

# Pick the one header whose path matches the requested platform.
pick_header() {
    local want="$1" matches
    matches=$(list_syscall_headers | grep -i "$want" || true)
    if [ -z "$matches" ]; then
        echo "error: no syscall.h matched platform '$want'" >&2
        list_platforms >&2
        exit 1
    fi
    # If a query is ambiguous, take the shortest path (the SDK's usr/include one).
    echo "$matches" | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2-
}

# Short description from the userland man page's NAME line, if one exists.
print_desc() {
    local name="$1" line
    line=$(man 2 "$name" 2>/dev/null | col -b \
        | awk '/^NAME/{getline; gsub(/^[[:space:]]+/,""); print; exit}')
    [ -n "$line" ] && { echo; echo "  desc:"; echo "    $line"; }
}

print_entry() {
    local sp="$1" name="$2" num="$3"
    printf '  %-28s %s\n' "SYS_${name}" "$num"

    print_desc "$name"

    [ -z "$sp" ] && return 0

    # Argument struct, with the PADL_/PADR_ alignment noise stripped out.
    if grep -q "^struct ${name}_args" "$sp" 2>/dev/null; then
        echo
        echo "  args:"
        awk "/^struct ${name}_args {/{f=1} f{print} /^};/{if(f)exit}" "$sp" \
            | sed -E 's/char [a-zA-Z0-9_]+_[lr]_\[[^]]*\];//g' \
            | sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g; s/ ;/;/g; s/ +$//' \
            | sed 's/^/    /'
    fi
    # Kernel prototype (return type).
    local proto
    proto=$(grep -E "^int (sys_)?${name}\(struct proc" "$sp" 2>/dev/null | head -1 || true)
    [ -n "$proto" ] && { echo; echo "  proto:"; echo "    $proto"; }
}

lookup() {
    local header="$1" query="$2" line name num found=0 sp
    # Resolve sysproto.h once, not once per match.
    sp=$(find_sysproto)
    echo "# $(echo "$header" | sed -E 's#.*/Platforms/([^/]+)\.platform/.*#\1#'): $header"
    echo

    if [[ "$query" =~ ^[0-9]+$ ]]; then
        # number -> name (exact match on the value column)
        while IFS= read -r line; do
            name=$(echo "$line" | awk '{print $2}' | sed 's/^SYS_//')
            num=$(echo "$line" | awk '{print $3}')
            print_entry "$sp" "$name" "$num"; found=1
        done < <(awk -v n="$query" '$1=="#define" && $2 ~ /^SYS_/ && $3==n' "$header")
    else
        # name substring -> matches
        while IFS= read -r line; do
            name=$(echo "$line" | awk '{print $2}' | sed 's/^SYS_//')
            num=$(echo "$line" | awk '{print $3}')
            print_entry "$sp" "$name" "$num"; found=1
        done < <(grep -iE "^#define[[:space:]]+SYS_[a-zA-Z0-9_]*${query}" "$header")
    fi

    if [ "$found" -eq 0 ]; then
        echo "  no match for '$query'" >&2
        echo >&2
        echo "  tip: 'man 2 $query' is the userland man page if one exists." >&2
        exit 1
    fi
}

# --- arg parsing ---
[ $# -eq 0 ] && usage 1
case "${1:-}" in
    -h|--help)    usage 0 ;;
    -r|--refresh) ensure_cache force; echo "cache rebuilt: $CACHE_DIR"; exit 0 ;;
    -l|--list)    ensure_cache; list_platforms; exit 0 ;;
esac

ensure_cache

if [ $# -ge 2 ]; then
    PLATFORM="$1"; QUERY="$2"
else
    PLATFORM="$DEFAULT_PLATFORM"; QUERY="$1"
fi

HEADER=$(pick_header "$PLATFORM")
lookup "$HEADER" "$QUERY"
