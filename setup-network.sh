#!/bin/sh
set -eu

DEST=/usr/local/libexec/monitor-menu-network
SUDOERS_DIR=/etc/sudoers.d

require_root() {
    [ "$(id -u)" -eq 0 ] || {
        echo "Ejecuta con sudo: sudo sh $0 ${1:-install}" >&2
        exit 77
    }
}

normal_user() {
    user=${SUDO_USER:-}
    if [ -z "$user" ] || [ "$user" = root ]; then
        echo "Ejecuta este instalador con sudo desde tu usuario normal." >&2
        exit 1
    fi
    case "$user" in *[!A-Za-z0-9._-]*) echo "Usuario no válido: $user" >&2; exit 1 ;; esac
    printf '%s\n' "$user"
}

install_helper() {
    require_root install
    user=$(normal_user)
    script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd)
    src=$script_dir/network-helper.sh
    [ -f "$src" ] || { echo "No se encontró network-helper.sh" >&2; exit 1; }

    for cmd in hostapd dnsmasq iw ip nmcli sudo visudo; do
        command -v "$cmd" >/dev/null 2>&1 || { echo "Falta $cmd" >&2; exit 127; }
    done

    sudoers=$SUDOERS_DIR/monitor-menu-network-$user
    tmp=$(mktemp)
    staged=$DEST.new.$$
    trap 'rm -f "$tmp" "$staged"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    {
        printf '%s ALL=(root) NOPASSWD: %s configure auto\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s configure current\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s configure bypass\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s start auto\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s start current\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s start bypass\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s stop\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s status\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s secret host\n' "$user" "$DEST"
        printf '%s ALL=(root) NOPASSWD: %s secret password\n' "$user" "$DEST"
    } > "$tmp"
    chmod 0440 "$tmp"
    visudo -cf "$tmp" >/dev/null

    sh -n "$src"
    install -d -m 0755 /usr/local/libexec "$SUDOERS_DIR"
    install -m 0755 -o root -g root "$src" "$staged"
    if [ -x "$DEST" ]; then
        "$DEST" stop >/dev/null 2>&1 || { echo "No se pudo detener el helper anterior" >&2; exit 1; }
    fi
    mv "$staged" "$DEST"
    rm -f "$sudoers"
    install -m 0440 -o root -g root "$tmp" "$sudoers"
    rm -f "$tmp"
    trap - EXIT HUP INT TERM
    printf 'network_helper=%s\nuser=%s\ninstalled=1\n' "$DEST" "$user"
}

remove_helper() {
    require_root remove
    user=$(normal_user)
    sudoers=$SUDOERS_DIR/monitor-menu-network-$user
    if [ -x "$DEST" ]; then
        "$DEST" stop >/dev/null 2>&1 || { echo "No se pudo limpiar la red; se conserva el helper" >&2; exit 1; }
    fi
    rm -f "$sudoers"
    rm -f "$DEST"
    printf 'installed=0\n'
}

case "${1:-install}" in
    install) install_helper ;;
    remove) remove_helper ;;
    *) echo "usage: sudo sh $0 {install|remove}" >&2; exit 2 ;;
esac
