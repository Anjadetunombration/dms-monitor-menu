#!/bin/sh
set -eu

# Installed root-owned by setup-vkms.sh. The plugin never runs this copy.
RUN_DIR=/run/monitor-menu-vkms
STATE_DIR=/var/lib/monitor-menu-vkms
STATE_FILE=$RUN_DIR/state
LOCK_DIR=$RUN_DIR/lock
OWNED_FILE=$STATE_DIR/owned

err() { printf 'monitor-menu-vkms: %s\n' "$*" >&2; }

require_root() {
    [ "$(id -u)" -eq 0 ] || {
        err "esta acción requiere root"
        exit 77
    }
}

ensure_dirs() {
    mkdir -p "$RUN_DIR" "$STATE_DIR"
    chmod 0755 "$RUN_DIR"
    chmod 0700 "$STATE_DIR"
}

require_owned() {
    [ -f "$OWNED_FILE" ] || {
        err "el módulo VKMS no pertenece a Monitor Menu"
        return 78
    }
}

write_state() {
    ensure_dirs
    tmp=$STATE_FILE.tmp.$$
    printf 'STATE=%s\n' "$1" > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$STATE_FILE"
}

acquire_lock() {
    ensure_dirs
    tries=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        set -- "$LOCK_DIR"/owner.*
        owner=
        [ ! -d "$1" ] || owner=${1##*.}
        case "$owner" in
            ''|*[!0-9]*)
                [ "$tries" -lt 20 ] || rmdir "$LOCK_DIR" 2>/dev/null || true
                ;;
            *)
                if ! kill -0 "$owner" 2>/dev/null; then
                    rmdir "$LOCK_DIR/owner.$owner" 2>/dev/null || true
                    rmdir "$LOCK_DIR" 2>/dev/null || true
                fi
                ;;
        esac
        tries=$((tries + 1))
        [ "$tries" -lt 100 ] || { err "otra operación VKMS sigue activa"; return 75; }
        sleep 0.1
    done
    mkdir "$LOCK_DIR/owner.$$" || { rmdir "$LOCK_DIR" 2>/dev/null || true; return 75; }
}

release_lock() {
    rmdir "$LOCK_DIR/owner.$$" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
}

module_loaded() {
    [ -d /sys/module/vkms ]
}

connector_present() {
    for connector in /sys/class/drm/card*-Virtual-*; do
        [ -e "$connector" ] && return 0
    done
    return 1
}

connector_path() {
    for connector in /sys/class/drm/card*-Virtual-*; do
        [ -e "$connector" ] || continue
        printf '%s\n' "$connector"
        return 0
    done
    return 1
}

connector_connected() {
    connector=$(connector_path 2>/dev/null || true)
    [ -n "$connector" ] && [ "$(sed -n '1p' "$connector/status" 2>/dev/null || true)" = connected ]
}

trigger_hotplug() {
    connector=$1
    name=${connector##*/}
    card=${name%%-*}
    [ ! -w "/sys/class/drm/$card/uevent" ] || printf 'change\n' > "/sys/class/drm/$card/uevent"
}

wait_active() {
    i=0
    while [ "$i" -lt 50 ]; do
        module_loaded && connector_connected && return 0
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

wait_absent() {
    i=0
    while [ "$i" -lt 50 ]; do
        ! connector_connected && return 0
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

cmd_create() {
    require_root
    require_owned
    command -v modprobe >/dev/null 2>&1 || { err "falta modprobe"; return 127; }
    acquire_lock
    trap 'release_lock' EXIT
    trap 'release_lock; exit 129' HUP
    trap 'release_lock; exit 130' INT
    trap 'release_lock; exit 143' TERM

    if module_loaded && connector_connected; then
        write_state ACTIVE
    else
        write_state CREATING
        if ! module_loaded && ! modprobe vkms; then
            write_state ERROR
            err "no se pudo crear el dispositivo VKMS"
            return 1
        fi
        connector=$(connector_path 2>/dev/null || true)
        if [ -z "$connector" ] || ! printf 'detect\n' > "$connector/status"; then
            write_state ERROR
            err "no se pudo conectar la salida VKMS"
            return 1
        fi
        trigger_hotplug "$connector"
        if ! wait_active; then
            write_state ERROR
            err "VKMS no confirmó la conexión"
            return 1
        fi
        write_state ACTIVE
    fi
}

cmd_destroy() {
    require_root
    require_owned
    command -v modprobe >/dev/null 2>&1 || { err "falta modprobe"; return 127; }
    acquire_lock
    trap 'release_lock' EXIT
    trap 'release_lock; exit 129' HUP
    trap 'release_lock; exit 130' INT
    trap 'release_lock; exit 143' TERM

    if ! module_loaded || ! connector_present; then
        write_state ABSENT
        return 0
    fi

    write_state DESTROYING
    connector=$(connector_path)
    if ! printf 'off\n' > "$connector/status"; then
        write_state ERROR
        err "no se pudo desconectar la salida VKMS"
        return 1
    fi
    trigger_hotplug "$connector"
    if ! wait_absent; then
        write_state ERROR
        err "VKMS no confirmó la desconexión"
        return 1
    fi
    write_state ABSENT
}

cmd_status() {
    require_root
    owned=0
    loaded=0
    connector=0
    connected=0
    [ -f "$OWNED_FILE" ] && owned=1
    module_loaded && loaded=1
    connector_present && connector=1
    connector_connected && connected=1

    if [ -r "$STATE_FILE" ]; then
        state=$(sed -n 's/^STATE=//p' "$STATE_FILE" | sed -n '1p')
    else
        state=
    fi
    case "$state" in ABSENT|CREATING|ACTIVE|DESTROYING|ERROR) ;; *) state=ABSENT ;; esac
    transition_active=0
    case "$state" in CREATING|DESTROYING) [ -d "$LOCK_DIR" ] && transition_active=1 ;; esac
    if [ "$transition_active" -eq 0 ]; then
        if [ "$loaded" -eq 1 ] && [ "$connected" -eq 1 ]; then
            state=ACTIVE
        elif [ "$connected" -eq 0 ]; then
            state=ABSENT
        fi
    fi

    printf 'owned=%s\nloaded=%s\nconnector=%s\nconnected=%s\nstate=%s\n' "$owned" "$loaded" "$connector" "$connected" "$state"
}

if [ "${MONITOR_MENU_SOURCE_ONLY:-0}" != 1 ]; then
    case "${1:-}" in
        create) [ "$#" -eq 1 ] || exit 2; cmd_create ;;
        destroy) [ "$#" -eq 1 ] || exit 2; cmd_destroy ;;
        status) [ "$#" -eq 1 ] || exit 2; cmd_status ;;
        *) echo "usage: $0 {create|destroy|status}" >&2; exit 2 ;;
    esac
fi
