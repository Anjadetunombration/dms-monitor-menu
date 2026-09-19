# Changelog

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
- Streaming de audio desactivado para usar Moonlight como segundo monitor visual.
