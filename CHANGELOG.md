# Changelog

## 0.8.1

### Fixed

- Corregido el estado de red que permanecía en `RECONFIGURING` por una colisión de variables POSIX tras iniciar correctamente la LAN privada.
- Bloqueadas las acciones de lifecycle virtual durante transiciones VKMS y mutaciones de red concurrentes.
- Evitado que un refresco de red pendiente se pierda detrás de otra consulta activa.
- El estado VKMS reconcilia transiciones interrumpidas cuando ya no existe una operación activa.
- La restauración automática conserva la preferencia ON después de un fallo transitorio de VKMS, Niri o Sunshine.
- Los PID files de Sunshine, wl-mirror, hostapd y dnsmasq ya no se aceptan sin validar el proceso gestionado.
- La tabla nftables solo se elimina cuando existe su marcador de ownership.

### Changed

- Separada la presentación QML en componentes de pantallas, modos, monitor virtual, red y LAN privada sin cambiar el UX.
- Las consultas `status` dejan de crear estado persistente o reescribir PID files.
- Añadido instalador explícito para releases descomprimidas y reorganizada la documentación pública.
- Actualizado el autor público del manifiesto sin incluir datos personales.

### Development

- Añadido CI con Dash, ShellCheck, validación del manifiesto, parser QML, tests y comprobación de árbol limpio.
- Añadidos fixtures y tests de helpers para estados `key=value`, campos obligatorios, modos y consultas sin efectos laterales.
- Añadidos formulario de bugs y checklist de release.

## 0.8.0

- Reducido el consumo en reposo: pantallas, duplicación, monitor virtual y red solo se consultan mientras el menú está visible, con refresco inmediato al abrirlo.
- Añadidos `Automático`, `Red actual` y `Bypass` como modos generales de red.
- Añadido helper root-owned con sudoers limitado; DMS no ejecuta scripts modificables por el usuario como root.
- Añadida LAN privada mediante hostapd/dnsmasq con SSID, clave y MAC local persistentes.
- El AP sigue el canal del uplink Wi-Fi y pasa a standalone con debounce cuando se pierde.
- El watcher pausa el AP durante asociaciones de NetworkManager, exige una asociación estable y aplica cooldown tras errores.
- Añadida compartición opcional de Internet con reglas nftables aisladas y forwarding por interfaz.
- Estado `key=value` dinámico para interfaz, SSID, host, banda, canal, clientes, uplink, routing y máquina de estados.
- `LAN privada` aparece solo cuando el AP está realmente activo.
- `Host` y `Clave` se ocultan por defecto, se vuelven a consultar al interactuar y se copian con Qt sin `wl-copy`.
- La clave se obtiene bajo demanda, no entra en el polling ni en PluginSettings y no se registra en logs.
- La red se inicia y limpia en todos los caminos que encienden o apagan `Virtual-1`, incluida la restauración de DMS.
- Corregida la propagación de errores de modo y Sunshine en el helper del monitor virtual.
- El arranque virtual publica su intención antes del hotplug y serializa operaciones para sobrevivir a la recreación de superficies de DMS.
- La restauración de `Virtual-1` es idempotente cuando Sunshine ya captura correctamente la salida.
- `Monitor virtual = OFF` fuerza ahora el connector VKMS a `disconnected`, emite hotplug y retira `Virtual-1` de Niri/DMS sin reiniciar la sesión.
- Añadido helper VKMS root-owned con ownership explícito, sudoers restringido, serialización y estados `ABSENT`, `CREATING`, `ACTIVE`, `DESTROYING` y `ERROR`.
- Sunshine se detiene antes de retirar el connector y el encendido espera a que Niri/DMS anuncien la salida antes de iniciar la captura.
- Eliminada la carga permanente de VKMS en nuevas instalaciones; el helper migra la configuración anterior de `modules-load.d`.
- Corregida la colisión global de IDs de `Proc.runCommand` entre instancias del plugin que dejaba `busy` y `networkBusy` bloqueados tras hotplug.
- Cada instancia usa ahora un namespace de procesos propio y pasa `owner` para descartar callbacks de componentes destruidos.
- La reconciliación y el polling de red ya no bloquean acciones de pantalla; sus flags permanecen separados.
- Resolución y Audio quedan atenuados solo con Virtual-1 apagado o en transición, y vuelven a ser interactivos en `ACTIVE`.
- Eliminado el volcado de diff accidental `wq`.

## 0.7.1

- Restaurado `Modo de pantalla` cuando `Virtual-1` es la única salida secundaria.
- `Solo principal` también apaga el monitor virtual.
- `Extender` vuelve a encender `Virtual-1` cuando está disponible.
- `Duplicar` puede usar `Virtual-1` como destino mediante `wl-mirror`.
- El estado `Solo principal` / `Duplicar` / `Extender` ahora cuenta también la salida virtual.

## 0.7.0

- Añadido selector de salida de audio para el monitor virtual.
- `Local`: el receptor virtual recibe solo video y el audio permanece en el equipo.
- `Virtual`: Sunshine transmite el audio al receptor virtual y evita duplicarlo en la salida local.
- La selección se guarda y se reaplica al encender el monitor virtual.
- Cambio de audio en caliente con reinicio controlado de Sunshine, sin apagar `Virtual-1`.
- La interfaz usa los nombres `Local` y `Virtual` para mantener coherencia con el resto del widget.

## 0.6.2

- Corregido el tamaño de la píldora en DankBar para evitar que el widget quede con ancho inválido o desaparezca.
- La píldora usa ahora `PluginComponent.widgetThickness` e `iconSize` directamente, sin depender del `Loader` padre.
- Añadido permiso `process` al manifest para reflejar el uso real de `Proc.runCommand`.

## 0.6.1

- Añadidos ajustes de apariencia para la píldora de DankBar.
- Padding opcional alrededor del icono.
- Espaciado configurable de 0 a 20 px.
- Sin cambios en la lógica de VKMS, Sunshine o audio.

## 0.6.0

- Selector de resolución virtual integrado en el popout.
- Presets filtrados según modos realmente anunciados por Niri/VKMS.
- Persistencia de la resolución elegida.
- Reinicio controlado de Sunshine al cambiar el modo mientras el monitor virtual está activo.
- Detección automática de pantalla principal.
- Sunshine puede ejecutarse nativamente o desde un estrato Bedrock.
- Texto de estado más claro: video remoto, audio local.
- Metadatos del plugin neutralizados para una futura publicación sin información personal.

## 0.5.2

- Espera activa de `Virtual-1` antes de arrancar Sunshine.
- Verificación de que Sunshine capture `Virtual-1` y no el primer monitor físico.
- Streaming de audio desactivado para usar el receptor virtual como segundo monitor visual.
