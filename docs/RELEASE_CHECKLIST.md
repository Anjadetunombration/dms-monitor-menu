# Release Checklist

## Repository

- [ ] `git status` está limpio.
- [ ] CI está verde para la rama que se publicará.
- [ ] `plugin.json` contiene la versión correcta.
- [ ] README no muestra una versión fija obsoleta.
- [ ] CHANGELOG contiene todos los cambios reales de la versión.
- [ ] No hay logs, estado local, credenciales, claves, certificados ni configuraciones privadas en Git.

## Clean Installation

- [ ] Instalar desde una carpeta limpia o desde el archivo final descomprimido.
- [ ] Ejecutar `./install.sh` como usuario normal.
- [ ] Verificar `setup-vkms.sh install`.
- [ ] Verificar `setup-network.sh install`.
- [ ] Confirmar que los helpers instalados son `root:root` y no son modificables por el usuario.
- [ ] Confirmar que las reglas sudoers pasan `visudo -cf`.
- [ ] Reiniciar DMS y revisar que no existan errores QML.

## Displays

- [ ] Probar una pantalla física.
- [ ] Probar hotplug de una pantalla física con el menú abierto y cerrado.
- [ ] Probar encender y apagar una salida física secundaria.
- [ ] Probar Monitor virtual ON y OFF.
- [ ] Confirmar que OFF retira `Virtual-1` de `niri msg outputs` y `dms randr --json`.
- [ ] Probar todas las resoluciones anunciadas.
- [ ] Probar Audio Local.
- [ ] Probar Audio Virtual.
- [ ] Probar Solo principal.
- [ ] Probar Extender.
- [ ] Probar Duplicar y la limpieza de procesos `wl-mirror`.
- [ ] Reiniciar DMS con el monitor virtual ON y OFF.

## Network And Sunshine

- [ ] Probar Automático.
- [ ] Probar Red actual.
- [ ] Probar Bypass.
- [ ] Probar uplink Wi-Fi de 5 GHz.
- [ ] Probar uplink Wi-Fi de 2.4 GHz.
- [ ] Probar funcionamiento sin uplink.
- [ ] Probar cambio de red/canal y recuperación del AP.
- [ ] Confirmar que host y clave solo se consultan al interactuar.
- [ ] Confirmar que estado y logs no contienen la contraseña.
- [ ] Confirmar que detener la red elimina procesos, interfaz y reglas propias.
- [ ] Confirmar `capture=virtual` en `virtual-monitor-helper.sh status`.
- [ ] Confirmar que Sunshine se detiene al apagar `Virtual-1`.

## Packaging

- [ ] Crear el `tar.gz` desde el commit o tag, no desde un árbol sucio.
- [ ] Inspeccionar el listado completo del archivo.
- [ ] Confirmar que el paquete no contiene `.git`, logs, estado ni secretos.
- [ ] Calcular y publicar SHA-256.
- [ ] Crear el tag de versión sin reescribir tags anteriores.
- [ ] Crear la release desde el tag.
- [ ] Adjuntar `tar.gz` y checksum.
- [ ] Instalar una vez desde el artefacto publicado.
