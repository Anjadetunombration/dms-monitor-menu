#!/bin/sh
set -eu

[ "$(id -u)" -ne 0 ] || {
    echo "Ejecuta ./install.sh como usuario normal; sudo se solicitará solo para los helpers." >&2
    exit 77
}

SOURCE_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DEST=$CONFIG_HOME/DankMaterialShell/plugins/MonitorMenu

for command_name in dms niri sudo install; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Falta la dependencia requerida: $command_name" >&2
        exit 127
    }
done

missing_network=
for command_name in hostapd dnsmasq iw ip nmcli; do
    command -v "$command_name" >/dev/null 2>&1 || missing_network="$missing_network $command_name"
done
[ -z "$missing_network" ] || {
    echo "Faltan dependencias de red:$missing_network" >&2
    exit 127
}

install -d -m 0755 "$DEST" "$DEST/components"
for file in plugin.json MonitorMenu.qml MonitorMenuSettings.qml; do
    install -m 0644 "$SOURCE_DIR/$file" "$DEST/$file"
done
for file in "$SOURCE_DIR"/components/*.qml; do
    install -m 0644 "$file" "$DEST/components/${file##*/}"
done
for file in mirror-helper.sh network-helper.sh setup-network.sh setup-vkms.sh virtual-monitor-helper.sh vkms-helper.sh; do
    install -m 0755 "$SOURCE_DIR/$file" "$DEST/$file"
done

sudo sh "$DEST/setup-vkms.sh" install
sudo sh "$DEST/setup-network.sh" install

printf 'Plugin instalado en %s\n' "$DEST"
printf '%s\n' 'Reinicia DMS con: dms restart'
