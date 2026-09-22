# Monitor Menu v0.8.0

Widget para DankMaterialShell (DMS) + Niri que gestiona pantallas físicas, `Virtual-1` mediante VKMS + Sunshine y una red adaptable para el monitor remoto.

## Funciones

- Detecta pantallas físicas y hotplug mediante `dms randr --json`.
- Protege la pantalla principal y permite encender o apagar las secundarias.
- Incluye `Solo principal`, `Duplicar` con `wl-mirror` y `Extender`.
- Crea o retira lógicamente `Virtual-1` dentro de la misma sesión Niri y fija Sunshine a esa salida.
- Ofrece resoluciones virtuales compatibles y audio `Local` o `Virtual`.
- Conserva el padding configurable de la píldora de DankBar.
- Añade `Modo de red`: `Automático`, `Red actual` y `Bypass`.
- Muestra `LAN privada` únicamente cuando el AP está realmente activo.

## Modos De Red

### Automático

Es el modo predeterminado. Intenta crear una LAN privada directa y, si el hardware o las herramientas no lo permiten, utiliza la red actual. La implementación técnica queda oculta para el usuario.

### Red actual

Sunshine y el receptor usan directamente la red a la que ya está conectado el equipo. No se crea una interfaz AP ni aparece la sección `LAN privada`.

### Bypass

Crea una LAN privada directa entre el equipo y el receptor. Si NetworkManager tiene una Wi-Fi asociada, el AP usa el mismo canal. Sin uplink, elige un canal permitido, prefiriendo 5 GHz no DFS. La LAN y Sunshine siguen funcionando sin Internet.

Cuando NetworkManager inicia una asociación, el watcher puede pausar brevemente el AP para liberar la radio. Tras una asociación estable reconstruye la LAN en el canal nuevo; si falla, vuelve a modo autónomo después de un debounce.

SSID, contraseña y MAC local administrada persisten en `/var/lib/monitor-menu-network`. La interfaz AP permanece fuera de la gestión de NetworkManager. Si existe conectividad real y `nft` está disponible, el helper comparte Internet únicamente entre la interfaz privada y la ruta de salida detectada.

## Estado Dinámico

La UI obtiene del sistema efectivo:

- interfaz AP y uplink;
- SSID, dirección del host, banda y canal;
- clientes asociados;
- estado de la máquina (`UPLINK`, `CONNECTING`, `STANDALONE` o `RECONFIGURING`);
- disponibilidad de Internet compartido.

`Host` y `Clave` están ocultos por defecto. Un clic izquierdo consulta el valor actual y lo muestra u oculta. Un clic derecho vuelve a consultarlo y lo copia mediante `TextInput.copy()` de Qt, sin depender de `wl-copy`. La clave no forma parte del polling normal ni se guarda en DMS.

## Requisitos

- Niri 26.04 o compatible
- DankMaterialShell 1.6 o posterior
- Quickshell 0.3 o posterior
- kernel con `vkms`
- Sunshine
- NetworkManager / `nmcli`
- `hostapd`
- `dnsmasq`
- `iw`
- `iproute2`
- `sudo` y `visudo`
- `nftables` para compartir Internet; la LAN local funciona sin `nft`
- `wl-mirror` para `Duplicar`
- `jq` recomendado para reportar con precisión el modo virtual activo

En Void Linux, las dependencias de red se instalan con:

```bash
sudo xbps-install -S NetworkManager hostapd dnsmasq iw iproute2 nftables sudo
```

No se necesita AUR ni se añade una dependencia para el portapapeles.

## Instalación

Instale o actualice el plugin:

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/MonitorMenu
cp -a MonitorMenu/. ~/.config/DankMaterialShell/plugins/MonitorMenu/
chmod +x ~/.config/DankMaterialShell/plugins/MonitorMenu/*.sh
```

Instale el helper VKMS privilegiado una vez:

```bash
sudo sh ~/.config/DankMaterialShell/plugins/MonitorMenu/setup-vkms.sh install
```

El instalador migra la configuración anterior de `/etc/modules-load.d`, copia el helper a `/usr/local/libexec/monitor-menu-vkms` como `root:root` y autoriza únicamente `create`, `destroy` y `status`. Al apagar el monitor, Sunshine se detiene primero y el connector se fuerza a `disconnected`; así `Virtual-1` desaparece de Niri/DMS aunque el módulo permanezca cargado mientras Niri conserve abierto el dispositivo DRM. Al encenderlo, el helper vuelve a detectar el connector y espera el hotplug antes de iniciar Sunshine.

Instale el helper de red privilegiado:

```bash
sudo sh ~/.config/DankMaterialShell/plugins/MonitorMenu/setup-network.sh install
```

El instalador copia el helper a `/usr/local/libexec/monitor-menu-network` como `root:root` y crea reglas sudoers limitadas a argumentos concretos. DMS nunca recibe permiso para ejecutar como root un script modificable dentro del plugin.

Reinicie DMS o vuelva a escanear sus plugins.

Para actualizar una instalación existente, reemplace los archivos del plugin y vuelva a ejecutar:

```bash
sudo sh ~/.config/DankMaterialShell/plugins/MonitorMenu/setup-network.sh install
sudo sh ~/.config/DankMaterialShell/plugins/MonitorMenu/setup-vkms.sh install
```

La actualización conserva modo, SSID, clave y MAC persistentes.

## Sunshine Y Audio

El helper mantiene `output_name = Virtual-1`.

`Audio > Local` configura:

```ini
output_name = Virtual-1
stream_audio = disabled
```

`Audio > Virtual` configura:

```ini
output_name = Virtual-1
stream_audio = enabled
virtual_sink = sink-sunshine-stereo
```

## Diagnóstico

Estado del monitor virtual:

```bash
~/.config/DankMaterialShell/plugins/MonitorMenu/virtual-monitor-helper.sh status
```

Estado root-owned de VKMS:

```bash
sudo -n /usr/local/libexec/monitor-menu-vkms status
```

Estado parseable de red, sin contraseña:

```bash
sudo -n /usr/local/libexec/monitor-menu-network status
```

Consultar los valores efectivos manualmente:

```bash
sudo -n /usr/local/libexec/monitor-menu-network secret host
sudo -n /usr/local/libexec/monitor-menu-network secret password
```

Últimos eventos del watcher:

```bash
sudo /usr/local/libexec/monitor-menu-network log 100
```

Si Moonlight acepta el PIN pero muestra `Certificate verification failed`, revise el log de Sunshine. Las versiones nocturnas anteriores a `2026.918.174827` pueden rechazar identidades duplicadas con `Client certificate identity is not enabled`; actualice Sunshine y elimine únicamente los registros duplicados, sin regenerar `cakey.pem` ni `cacert.pem`.

## Pruebas Manuales

Active `Monitor virtual` y deje `Modo de red > Automático` o seleccione `Bypass`. Durante cada transición observe:

```bash
while sleep 1; do sudo -n /usr/local/libexec/monitor-menu-network status; done
sudo /usr/local/libexec/monitor-menu-network log 100
iw dev
ip -4 addr
```

Compruebe, en orden:

1. Wi-Fi 5 GHz: AP y uplink muestran el mismo canal; conecte el receptor.
2. Cambie a una Wi-Fi 2.4 GHz: el estado pasa por adaptación y reaparece con el mismo SSID y clave.
3. Desconecte el uplink: tras el debounce aparece `STANDALONE`, preferentemente en 5 GHz.
4. Desde standalone, conecte una Wi-Fi nueva: el AP se pausa si hace falta y reaparece en el canal asociado.
5. Con conectividad `full`, `internet=shared`; sin Internet, Sunshine sigue accesible por el host privado.
6. Seleccione `Red actual`: `lan_active=0` y `mm-ap0` no debe existir.
7. Seleccione `Bypass`: despliegue `LAN privada` y pruebe revelar/copiar `Host` y `Clave`.
8. Apague `Monitor virtual`: desaparecen AP, procesos y reglas propias sin cambiar la Wi-Fi principal.
9. Confirme además que `Virtual-1` ya no aparece en `niri msg outputs` ni en `dms randr --json`, aunque `/sys/module/vkms` pueda seguir presente.
10. Enciéndalo de nuevo y confirme que modo, SSID, clave, resolución y audio se restauran.
11. Reinicie DMS y verifique `capture=virtual` en el estado del monitor.

No ejecute las pruebas de cambio de canal durante una sesión remota que no pueda recuperar localmente.

## Desinstalación

Elimine primero la infraestructura y autorización de red:

```bash
sudo sh ~/.config/DankMaterialShell/plugins/MonitorMenu/setup-network.sh remove
sudo sh ~/.config/DankMaterialShell/plugins/MonitorMenu/setup-vkms.sh remove
```

El instalador verifica primero la limpieza de procesos, interfaz, forwarding y reglas propias. Solo después borra el helper y sudoers; si la limpieza falla conserva el helper y devuelve un error para permitir el diagnóstico. Los secretos persistentes permanecen en `/var/lib/monitor-menu-network` para una futura reinstalación; puede eliminarlos manualmente si ya no los necesita.

## Seguridad

- El helper autorizado es root-owned y acepta un conjunto cerrado de operaciones y modos.
- El helper VKMS solo puede conectar, desconectar y consultar la salida que pertenece a Monitor Menu; no descarga módulos a la fuerza ni termina el compositor.
- La configuración, contraseña y MAC persistentes usan permisos root-only.
- El estado periódico no contiene la contraseña.
- Las reglas nftables tienen tabla propia y limitan forwarding a la LAN privada y a la ruta detectada.
- `ap_isolate=1` impide comunicación directa entre clientes del AP.
- Un cliente que conozca la clave puede acceder a servicios que el equipo exponga en la interfaz privada, incluido Sunshine; trate esa clave como un secreto.
- El portapapeles del escritorio puede conservar temporalmente un valor copiado incluso después de ocultarlo en el widget.

## Variables Opcionales

El monitor virtual conserva `MONITOR_MENU_VIRTUAL_OUTPUT` y `MONITOR_MENU_SUNSHINE_STRATUM`; sus valores predeterminados son `Virtual-1` y `arch`. La UI de red no presupone nombres ni direcciones: siempre muestra el estado efectivo del helper.
