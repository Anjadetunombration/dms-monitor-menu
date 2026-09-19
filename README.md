# Monitor Menu v0.7.1

Widget para DankMaterialShell (DMS) + Niri que gestiona pantallas físicas y un segundo monitor virtual basado en VKMS + Sunshine.

## Funciones

- Detecta pantallas físicas con `dms randr --json` y actualiza el estado sin reiniciar DMS.
- Protege la pantalla principal para evitar apagarla desde el menú.
- Ofrece `Solo principal`, `Duplicar` (con `wl-mirror`) y `Extender` cuando existe una salida secundaria, incluida `Virtual-1`.
- Gestiona `Virtual-1` como un monitor real dentro de la misma sesión de Niri.
- Arranca Sunshine solo cuando `Virtual-1` ya está anunciado y verifica que Sunshine capture el monitor correcto.
- Permite elegir la salida de audio del monitor virtual: `Local` o `Virtual`.
- Permite elegir resolución virtual desde el widget. Solo muestra presets que VKMS/Niri anuncian realmente.
- Guarda la resolución elegida para el siguiente encendido del monitor virtual.
- Detecta automáticamente la salida principal, prefiriendo un panel `eDP-*` cuando existe.
- Incluye ajustes visuales del widget: padding opcional y espaciado configurable en la DankBar.

## Apariencia en la barra

Desde los ajustes del plugin puede activarse o desactivarse el padding del icono y elegir el espaciado entre 0 y 20 px. El valor predeterminado es 6 px.

Esto solo cambia el tamaño visual de la píldora en DankBar; no afecta al popout ni a la lógica de monitores.

## Resoluciones

El menú filtra dinámicamente los presets compatibles. Entre los candidatos están:

- 1280×720 @ 60 Hz
- 1600×900 @ 60 Hz
- 1920×1080 @ 60 Hz
- 2048×1152 @ 60 Hz
- 2560×1440 @ 60 Hz, si VKMS lo anuncia
- 3840×2160 @ 60 Hz, si VKMS lo anuncia

Al cambiar resolución con el monitor virtual encendido, Sunshine se reinicia para volver a capturar el output con el modo nuevo.

## Requisitos

- Niri
- DankMaterialShell 1.6 o posterior
- kernel con módulo `vkms`
- Sunshine
- `jq` recomendado para reportar el modo activo con precisión
- `wl-mirror` para el modo `Duplicar`, tanto en salidas físicas secundarias como en `Virtual-1`

Sunshine puede estar instalado de forma nativa. En Bedrock Linux también se admite Sunshine dentro de un estrato; por defecto se usa `arch`. Puede cambiarse con:

```bash
MONITOR_MENU_SUNSHINE_STRATUM=otro-estrato
```

## Instalación

Copie la carpeta `MonitorMenu` a:

```text
~/.config/DankMaterialShell/plugins/MonitorMenu
```

Dé permisos a los helpers:

```bash
chmod +x ~/.config/DankMaterialShell/plugins/MonitorMenu/*.sh
```

Configure VKMS una sola vez:

```bash
sudo sh ~/.config/DankMaterialShell/plugins/MonitorMenu/setup-vkms.sh install
```

Después reinicie DMS o vuelva a escanear plugins.

## Sunshine y audio

El helper mantiene `output_name = Virtual-1` y gestiona dos modos de audio desde el propio widget:

### Local

```ini
output_name = Virtual-1
stream_audio = disabled
```

El receptor virtual recibe solo video y el audio continúa en PipeWire/WirePlumber, Bluetooth, altavoces o la salida local seleccionada en el host.

### Virtual

```ini
output_name = Virtual-1
stream_audio = enabled
virtual_sink = sink-sunshine-stereo
```

El audio se transmite al receptor virtual y Sunshine usa su sink virtual para evitar duplicarlo en la salida local del host.

La selección se guarda en el estado del plugin y puede cambiarse con `Virtual-1` encendido; Sunshine se reinicia de forma controlada para aplicar el nuevo modo sin apagar el monitor virtual.

## Diagnóstico

Estado:

```bash
~/.config/DankMaterialShell/plugins/MonitorMenu/virtual-monitor-helper.sh status
```

Con el monitor virtual activo se espera algo equivalente a:

```text
present=1
enabled=1
sunshine=1
width=1920
height=1080
refresh=60000
audio=local
capture=virtual
```

Modos disponibles:

```bash
~/.config/DankMaterialShell/plugins/MonitorMenu/virtual-monitor-helper.sh modes
```

Cambiar audio manualmente:

```bash
~/.config/DankMaterialShell/plugins/MonitorMenu/virtual-monitor-helper.sh set-audio local
~/.config/DankMaterialShell/plugins/MonitorMenu/virtual-monitor-helper.sh set-audio virtual
```

Log de Sunshine gestionado por el widget:

```bash
~/.config/DankMaterialShell/plugins/MonitorMenu/virtual-monitor-helper.sh log 80
```

## Variables opcionales

```text
MONITOR_MENU_VIRTUAL_OUTPUT
MONITOR_MENU_SUNSHINE_STRATUM
```

Los valores por defecto son `Virtual-1` y `arch` respectivamente.
