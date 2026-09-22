#!/bin/sh
set -eu

runtime_dir="${XDG_RUNTIME_DIR:-/tmp/monitor-menu-$(id -u)}"
pidfile="$runtime_dir/monitor-menu-wl-mirror.pids"

mirror_pid_running() {
    pid=$1
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    [ "$pid" -gt 1 ] || return 1
    [ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" = wl-mirror ] \
        && kill -0 "$pid" 2>/dev/null
}

stop_mirrors() {
    if [ -f "$pidfile" ]; then
        while IFS= read -r pid; do
            mirror_pid_running "$pid" || continue
            kill "$pid" 2>/dev/null || true
        done < "$pidfile"
        rm -f "$pidfile"
    fi
}

status_mirrors() {
    [ -f "$pidfile" ] || {
        printf '%s\n' inactive
        return 0
    }

    while IFS= read -r pid; do
        if mirror_pid_running "$pid"; then
            printf '%s\n' active
            return 0
        fi
    done < "$pidfile"

    printf '%s\n' inactive
}

case "${1:-}" in
    start)
        shift
        source="${1:-}"
        [ -n "$source" ] || exit 2
        shift

        command -v wl-mirror >/dev/null 2>&1 || exit 127

        mkdir -p "$runtime_dir"
        chmod 0700 "$runtime_dir"
        stop_mirrors
        : > "$pidfile"

        for target in "$@"; do
            [ -n "$target" ] || continue
            niri msg output "$target" on >/dev/null 2>&1 || true
            sleep 0.20
            niri msg action focus-monitor "$target" >/dev/null 2>&1 || true
            sleep 0.20
            wl-mirror --fullscreen "$source" >/dev/null 2>&1 &
            printf '%s\n' "$!" >> "$pidfile"
            sleep 0.30
        done

        niri msg action focus-monitor "$source" >/dev/null 2>&1 || true
        ;;

    stop)
        stop_mirrors
        ;;

    status)
        status_mirrors
        ;;

    *)
        echo "usage: $0 {start SOURCE TARGET...|stop|status}" >&2
        exit 2
        ;;
esac
