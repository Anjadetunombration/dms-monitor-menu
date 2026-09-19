#!/bin/sh
set -eu

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
pidfile="$runtime_dir/monitor-menu-wl-mirror.pids"

stop_mirrors() {
    if [ -f "$pidfile" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill "$pid" 2>/dev/null || true
        done < "$pidfile"
        rm -f "$pidfile"
    fi
}

status_mirrors() {
    [ -f "$pidfile" ] || {
        printf '%s\n' inactive
        exit 0
    }

    alive=0
    tmp="${pidfile}.tmp"
    : > "$tmp"

    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        if kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$pid" >> "$tmp"
            alive=$((alive + 1))
        fi
    done < "$pidfile"

    if [ "$alive" -gt 0 ]; then
        mv "$tmp" "$pidfile"
        printf '%s\n' active
    else
        rm -f "$tmp" "$pidfile"
        printf '%s\n' inactive
    fi
}

case "${1:-}" in
    start)
        shift
        source="${1:-}"
        [ -n "$source" ] || exit 2
        shift

        command -v wl-mirror >/dev/null 2>&1 || exit 127

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
