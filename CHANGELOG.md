# Changelog

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
