#!/bin/sh
set -eu

virtual_output="${MONITOR_MENU_VIRTUAL_OUTPUT:-Virtual-1}"
arch_stratum="${MONITOR_MENU_SUNSHINE_STRATUM:-arch}"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/monitor-menu"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine"
state_file="$state_dir/virtual.state"
mode_file="$state_dir/virtual.mode"
audio_file="$state_dir/virtual.audio"
sunshine_pidfile="$runtime_dir/monitor-menu-sunshine.pid"
sunshine_log="$cache_dir/monitor-menu-sunshine.log"
sunshine_conf="$config_dir/sunshine.conf"
default_mode="1920x1080@60.000"
default_audio_mode="local"

mkdir -p "$state_dir" "$cache_dir" "$config_dir"

niri_outputs() {
    niri msg outputs 2>/dev/null || true
}

virtual_present() {
    niri_outputs | grep -Fq "($virtual_output)"
}

virtual_state() {
    niri_outputs | awk -v target="($virtual_output)" '
        /^Output / {
            inside = index($0, target) > 0
            next
        }
        inside && /^  Disabled$/ {
            print "off"
            found = 1
            exit
        }
        inside && /^  Current mode:/ {
            print "on"
            found = 1
            exit
        }
        END {
            if (!found) print "missing"
        }
    ' | head -n 1
}

available_virtual_modes_raw() {
    niri_outputs | awk -v target="($virtual_output)" '
        /^Output / {
            if (inside && seen_modes) exit
            inside = index($0, target) > 0
            seen_modes = 0
            next
        }
        inside && /^  Available modes:/ {
            seen_modes = 1
            next
        }
        inside && seen_modes && /^    [0-9]+x[0-9]+@/ {
            print $1
            next
        }
        inside && seen_modes && !/^    / {
            exit
        }
    '
}

mode_available() {
    wanted="$1"
    available_virtual_modes_raw | grep -Fxq "$wanted"
}

print_modes() {
    # Presets útiles para streaming; solo se muestran si el VKMS actual los anuncia.
    for entry in \
        '1280x720@60.000|720p' \
        '1600x900@60.000|900p' \
        '1920x1080@60.000|1080p' \
        '2048x1152@60.000|1152p' \
        '2560x1440@60.000|1440p' \
        '3840x2160@60.000|2160p'
    do
        mode=${entry%%|*}
        label=${entry#*|}
        if mode_available "$mode"; then
            printf '%s|%s\n' "$mode" "$label"
        fi
    done
}

valid_mode_format() {
    printf '%s\n' "$1" | grep -Eq '^[0-9]+x[0-9]+@[0-9]+([.][0-9]+)?$'
}

desired_mode() {
    mode="$default_mode"
    if [ -f "$mode_file" ]; then
        candidate="$(cat "$mode_file" 2>/dev/null || true)"
        if valid_mode_format "$candidate"; then
            mode="$candidate"
        fi
    fi
    printf '%s\n' "$mode"
}

persist_mode() {
    printf '%s\n' "$1" > "$mode_file"
}

valid_audio_mode() {
    case "$1" in
        local|virtual) return 0 ;;
        *) return 1 ;;
    esac
}

desired_audio_mode() {
    mode="$default_audio_mode"
    if [ -f "$audio_file" ]; then
        candidate="$(cat "$audio_file" 2>/dev/null || true)"
        if valid_audio_mode "$candidate"; then
            mode="$candidate"
        fi
    fi
    printf '%s\n' "$mode"
}

persist_audio_mode() {
    printf '%s\n' "$1" > "$audio_file"
}

parse_mode() {
    mode="$1"
    geometry=${mode%@*}
    refresh=${mode#*@}
    width=${geometry%x*}
    height=${geometry#*x}
    # millihertz for the QML/status interface
    refresh_mhz="$(awk -v r="$refresh" 'BEGIN { printf "%d", (r * 1000) + 0.5 }')"
    printf '%s %s %s\n' "$width" "$height" "$refresh_mhz"
}

virtual_advertised() {
    if command -v dms >/dev/null 2>&1; then
        dms randr --json 2>/dev/null \
            | grep -Fq '"name":"'"$virtual_output"'"'
        return $?
    fi
    [ "$(virtual_state)" = "on" ]
}

wait_virtual_ready() {
    i=0
    while [ "$i" -lt 50 ]; do
        if [ "$(virtual_state)" = "on" ] && virtual_advertised; then
            return 0
        fi
        sleep 0.10
        i=$((i + 1))
    done
    return 1
}

sunshine_running() {
    if [ -f "$sunshine_pidfile" ]; then
        pid="$(cat "$sunshine_pidfile" 2>/dev/null || true)"
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 0
    fi
    return 1
}

adopt_sunshine() {
    sunshine_running && return 0
    pid="$(pgrep -u "$(id -u)" -x sunshine 2>/dev/null | head -n 1 || true)"
    if [ -n "$pid" ]; then
        printf '%s\n' "$pid" > "$sunshine_pidfile"
        return 0
    fi
    return 1
}

stop_sunshine() {
    pids=""
    if [ -f "$sunshine_pidfile" ]; then
        pid="$(cat "$sunshine_pidfile" 2>/dev/null || true)"
        [ -n "$pid" ] && pids="$pid"
    fi
    extra="$(pgrep -u "$(id -u)" -x sunshine 2>/dev/null || true)"
    [ -n "$extra" ] && pids="$pids $extra"

    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done

    i=0
    while [ "$i" -lt 30 ]; do
        alive=0
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                alive=1
                break
            fi
        done
        [ "$alive" -eq 0 ] && break
        sleep 0.10
        i=$((i + 1))
    done

    for pid in $pids; do
        kill -KILL "$pid" 2>/dev/null || true
    done

    rm -f "$sunshine_pidfile"
}

sunshine_backend() {
    if command -v strat >/dev/null 2>&1 \
        && strat "$arch_stratum" sh -lc 'command -v sunshine >/dev/null 2>&1'; then
        printf '%s\n' strat
        return 0
    fi
    if command -v sunshine >/dev/null 2>&1; then
        printf '%s\n' native
        return 0
    fi
    return 1
}

sunshine_available() {
    sunshine_backend >/dev/null 2>&1
}

set_conf_value() {
    key="$1"
    value="$2"
    touch "$sunshine_conf"

    if grep -q "^${key}[[:space:]]*=" "$sunshine_conf"; then
        sed -i "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$sunshine_conf"
    else
        printf '\n%s = %s\n' "$key" "$value" >> "$sunshine_conf"
    fi
}

unset_conf_value() {
    key="$1"
    [ -f "$sunshine_conf" ] || return 0
    sed -i "/^${key}[[:space:]]*=/d" "$sunshine_conf"
}

configure_sunshine() {
    set_conf_value output_name "$virtual_output"

    case "$(desired_audio_mode)" in
        virtual)
            # Audio remoto: Sunshine transmite el audio y usa su sink virtual
            # para evitar duplicarlo en la salida local del host.
            set_conf_value stream_audio "enabled"
            set_conf_value virtual_sink "sink-sunshine-stereo"
            ;;
        *)
            # Audio local: el monitor virtual transmite solo video.
            unset_conf_value virtual_sink
            set_conf_value stream_audio "disabled"
            ;;
    esac
}

position_virtual_right_of() {
    primary="${1:-eDP-1}"

    geometry="$(
        niri_outputs | awk -v target="($primary)" '
            /^Output / {
                inside = index($0, target) > 0
                next
            }
            inside && /^  Logical position:/ {
                x = $3
                gsub(/,/, "", x)
                y = $4
            }
            inside && /^  Logical size:/ {
                split($3, s, "x")
                w = s[1]
                h = s[2]
            }
            inside && x != "" && y != "" && w != "" {
                print x, y, w, h
                exit
            }
        '
    )"

    [ -n "$geometry" ] || return 0

    # shellcheck disable=SC2086
    set -- $geometry
    x="$1"
    y="$2"
    w="$3"
    next_x=$((x + w))

    niri msg output "$virtual_output" position set "$next_x" "$y" >/dev/null 2>&1 || true
}

launch_sunshine_once() {
    wayland_display="${WAYLAND_DISPLAY:-wayland-1}"
    : > "$sunshine_log"

    backend="$(sunshine_backend)" || return 127
    if [ "$backend" = "strat" ]; then
        nohup env \
            WAYLAND_DISPLAY="$wayland_display" \
            XDG_SESSION_TYPE=wayland \
            strat "$arch_stratum" sunshine \
            > "$sunshine_log" 2>&1 &
    else
        nohup env \
            WAYLAND_DISPLAY="$wayland_display" \
            XDG_SESSION_TYPE=wayland \
            sunshine \
            > "$sunshine_log" 2>&1 &
    fi
    pid="$!"
    printf '%s\n' "$pid" > "$sunshine_pidfile"

    i=0
    while [ "$i" -lt 50 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$sunshine_pidfile"
            return 21
        fi

        selected="$(grep -F '[wlgrab] Selected monitor' "$sunshine_log" 2>/dev/null | tail -n 1 || true)"
        if [ -n "$selected" ]; then
            echo "$selected" | grep -Fq -- "- $virtual_output]" && return 0
            return 23
        fi

        sleep 0.10
        i=$((i + 1))
    done

    return 24
}

start_sunshine() {
    sunshine_available || return 127
    configure_sunshine
    wait_virtual_ready || return 25

    adopt_sunshine || true
    stop_sunshine

    attempt=1
    while [ "$attempt" -le 3 ]; do
        if launch_sunshine_once; then
            return 0
        fi
        rc=$?
        stop_sunshine
        [ "$rc" -eq 23 ] || [ "$rc" -eq 24 ] || return "$rc"
        sleep 0.50
        wait_virtual_ready || return 25
        attempt=$((attempt + 1))
    done

    return 23
}

apply_mode() {
    mode="$1"
    valid_mode_format "$mode" || return 26
    mode_available "$mode" || return 27
    niri msg output "$virtual_output" mode "$mode" >/dev/null 2>&1 || return 28
}

start_virtual() {
    primary="${1:-eDP-1}"
    mode="$(desired_mode)"

    virtual_present || return 20

    niri msg output "$virtual_output" on >/dev/null 2>&1 || return 22
    if ! apply_mode "$mode"; then
        rc=$?
        niri msg output "$virtual_output" off >/dev/null 2>&1 || true
        return "$rc"
    fi
    position_virtual_right_of "$primary"

    wait_virtual_ready || {
        niri msg output "$virtual_output" off >/dev/null 2>&1 || true
        return 25
    }

    if ! start_sunshine; then
        rc=$?
        niri msg output "$virtual_output" off >/dev/null 2>&1 || true
        return "$rc"
    fi

    printf '%s\n' on > "$state_file"
}

stop_virtual() {
    stop_sunshine
    if virtual_present; then
        niri msg output "$virtual_output" off >/dev/null 2>&1 || true
    fi
    printf '%s\n' off > "$state_file"
}

set_virtual_mode() {
    mode="$1"
    primary="${2:-eDP-1}"

    virtual_present || return 20
    valid_mode_format "$mode" || return 26
    mode_available "$mode" || return 27

    # Si está apagado, solo guarda el preset para el próximo arranque.
    if [ "$(virtual_state)" != "on" ]; then
        persist_mode "$mode"
        return 0
    fi

    stop_sunshine
    if ! apply_mode "$mode"; then
        rc=$?
        start_sunshine || true
        return "$rc"
    fi

    persist_mode "$mode"
    position_virtual_right_of "$primary"
    wait_virtual_ready || return 25
    start_sunshine
}

set_virtual_audio() {
    mode="$1"
    valid_audio_mode "$mode" || return 29

    persist_audio_mode "$mode"
    configure_sunshine

    # Si el monitor virtual está activo, reinicia Sunshine para aplicar
    # el cambio de audio sin apagar Virtual-1.
    if [ "$(virtual_state)" = "on" ]; then
        start_sunshine
    fi
}

init_virtual() {
    primary="${1:-eDP-1}"
    state=""

    [ -f "$mode_file" ] || persist_mode "$default_mode"
    [ -f "$audio_file" ] || persist_audio_mode "$default_audio_mode"

    if [ -f "$state_file" ]; then
        state="$(cat "$state_file" 2>/dev/null || true)"
    fi

    if [ -z "$state" ]; then
        if [ "$(virtual_state)" = "on" ]; then
            printf '%s\n' on > "$state_file"
            state="on"
        else
            printf '%s\n' off > "$state_file"
            state="off"
        fi
    fi

    case "$state" in
        on)
            start_virtual "$primary" || true
            ;;
        *)
            stop_sunshine
            if [ "$(virtual_state)" = "on" ]; then
                niri msg output "$virtual_output" off >/dev/null 2>&1 || true
            fi
            ;;
    esac
}

selected_capture() {
    line="$(grep -F '[wlgrab] Selected monitor' "$sunshine_log" 2>/dev/null | tail -n 1 || true)"
    if [ -z "$line" ]; then
        printf '%s\n' unknown
    elif echo "$line" | grep -Fq -- "- $virtual_output]"; then
        printf '%s\n' virtual
    else
        printf '%s\n' wrong
    fi
}

print_status() {
    present=0
    enabled=0
    sunshine=0

    mode="$(desired_mode)"
    # shellcheck disable=SC2086
    set -- $(parse_mode "$mode")
    width="$1"
    height="$2"
    refresh="$3"

    virtual_present && present=1
    [ "$(virtual_state)" = "on" ] && enabled=1
    sunshine_running && sunshine=1

    if [ "$enabled" -eq 1 ] && command -v dms >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        row="$(
            dms randr --json 2>/dev/null \
                | jq -r --arg name "$virtual_output" \
                    '.outputs[]? | select(.name == $name) | "\(.width) \(.height) \(.refresh)"' \
                | head -n 1
        )"
        if [ -n "$row" ]; then
            # shellcheck disable=SC2086
            set -- $row
            width="$1"
            height="$2"
            refresh="$3"
        fi
    fi

    printf 'present=%s\n' "$present"
    printf 'enabled=%s\n' "$enabled"
    printf 'sunshine=%s\n' "$sunshine"
    printf 'width=%s\n' "$width"
    printf 'height=%s\n' "$height"
    printf 'refresh=%s\n' "$refresh"
    printf 'mode=%s\n' "$mode"
    printf 'audio=%s\n' "$(desired_audio_mode)"
    printf 'capture=%s\n' "$(selected_capture)"
}

case "${1:-}" in
    start)
        start_virtual "${2:-eDP-1}"
        ;;
    stop)
        stop_virtual
        ;;
    init)
        init_virtual "${2:-eDP-1}"
        ;;
    set-mode)
        [ "$#" -ge 2 ] || { echo "missing mode" >&2; exit 2; }
        set_virtual_mode "$2" "${3:-eDP-1}"
        ;;
    set-audio)
        [ "$#" -ge 2 ] || { echo "missing audio mode" >&2; exit 2; }
        set_virtual_audio "$2"
        ;;
    modes)
        print_modes
        ;;
    status)
        print_status
        ;;
    log)
        tail -n "${2:-80}" "$sunshine_log" 2>/dev/null || true
        ;;
    *)
        echo "usage: $0 {start [PRIMARY]|stop|init [PRIMARY]|set-mode MODE [PRIMARY]|set-audio local|virtual|modes|status|log [N]}" >&2
        exit 2
        ;;
esac
