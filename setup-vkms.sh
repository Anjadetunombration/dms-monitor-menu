#!/bin/sh
set -eu

DEST=/usr/local/libexec/monitor-menu-vkms
SUDOERS_DIR=/etc/sudoers.d
STATE_DIR=/var/lib/monitor-menu-vkms
OWNED_FILE=$STATE_DIR/owned
LEGACY_CONF=/etc/modules-load.d/monitor-menu-vkms.conf

require_root() {
    [ "$(id -u)" -eq 0 ] || {
        echo "Ejecuta con sudo: sudo sh $0 ${1:-install}" >&2
        exit 77
    }
}

normal_user() {
    user=${SUDO_USER:-}
    [ -n "$user" ] && [ "$user" != root ] || {
        echo "Ejecuta este instalador con sudo desde tu usuario normal." >&2
        exit 1
    }
    case "$user" in *[!A-Za-z0-9._-]*) echo "Usuario no válido: $user" >&2; exit 1 ;; esac
    printf '%s\n' "$user"
}

legacy_conf_owned() {
    [ -f "$LEGACY_CONF" ] || return 1
    awk '
        /^[[:space:]]*(#|$)/ { next }
        /^[[:space:]]*vkms[[:space:]]*$/ { found=1; next }
        { bad=1 }
        END { exit !(found && !bad) }
    ' "$LEGACY_CONF"
}

install_helper() {
    require_root install
    user=$(normal_user)
    script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
    src=$script_dir/vkms-helper.sh
    [ -f "$src" ] || { echo "No se encontró vkms-helper.sh" >&2; exit 1; }
    for cmd in modprobe sudo visudo; do
        command -v "$cmd" >/dev/null 2>&1 || { echo "Falta $cmd" >&2; exit 127; }
    done

    if [ -d /sys/module/vkms ] && [ ! -f "$OWNED_FILE" ] && ! legacy_conf_owned; then
        echo "VKMS ya está cargado y no pertenece a Monitor Menu; no se tomará control." >&2
        exit 78
    fi

    sudoers=$SUDOERS_DIR/monitor-menu-vkms-$user
    tmp=$(mktemp)
    staged=$DEST.new.$$
    trap 'rm -f "$tmp" "$staged"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    {
        printf '%s ALL=(root) NOPASSWD: %s create\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s destroy\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s status\n' "$user" "$DEST"
    } > "$tmp"
    chmod 0440 "$tmp"
    visudo -cf "$tmp" >/dev/null
    sh -n "$src"

    install -d -m 0755 /usr/local/libexec "$SUDOERS_DIR"
    install -d -m 0700 -o root -g root "$STATE_DIR"
    install -m 0755 -o root -g root "$src" "$staged"
    mv "$staged" "$DEST"
    : > "$OWNED_FILE"
    chmod 0600 "$OWNED_FILE"
    rm -f "$LEGACY_CONF"
    rm -f "$SUDOERS_DIR"/monitor-menu-vkms-*
    install -m 0440 -o root -g root "$tmp" "$sudoers"
    rm -f "$tmp"
    trap - EXIT HUP INT TERM
    printf 'vkms_helper=%s\nuser=%s\ninstalled=1\n' "$DEST" "$user"
}

remove_helper() {
    require_root remove
    if [ -x "$DEST" ]; then
        "$DEST" destroy >/dev/null 2>&1 || {
            echo "No se pudo desconectar VKMS; apaga el monitor virtual antes de desinstalar." >&2
            exit 1
        }
    fi
    rm -f "$LEGACY_CONF"
    rm -f "$SUDOERS_DIR"/monitor-menu-vkms-*
    rm -f "$OWNED_FILE" "$DEST"
    rmdir "$STATE_DIR" 2>/dev/null || true
    printf 'installed=0\n'
}

case "${1:-install}" in
    install) install_helper ;;
    remove) remove_helper ;;
    *) echo "usage: sudo sh $0 {install|remove}" >&2; exit 2 ;;
esac
