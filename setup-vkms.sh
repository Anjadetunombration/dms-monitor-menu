#!/bin/sh
set -eu

conf=/etc/modules-load.d/monitor-menu-vkms.conf

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Ejecuta con sudo: sudo sh $0 ${1:-install}" >&2
        exit 1
    fi
}

case "${1:-install}" in
    install)
        need_root install
        mkdir -p /etc/modules-load.d
        printf '%s\n' vkms > "$conf"
        modprobe vkms
        echo "VKMS configurado para cargarse al arrancar: $conf"
        ;;
    remove)
        need_root remove
        rm -f "$conf"
        echo "Persistencia de VKMS eliminada. El módulo cargado se deja intacto hasta reiniciar."
        ;;
    *)
        echo "usage: sudo sh $0 {install|remove}" >&2
        exit 2
        ;;
esac
