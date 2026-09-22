import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "components" as Components

PluginComponent {
    id: root

    property var popoutService: null

    // El principal jamás se apaga desde este menú.
    property string primaryOutput: "eDP-1"
    property string virtualOutput: "Virtual-1"

    property var outputs: []
    property string lastError: ""
    property bool busy: false
    property bool modesExpanded: false
    property bool resolutionExpanded: false
    property bool audioExpanded: false
    property bool networkExpanded: false
    property bool privateLanExpanded: false
    property bool networkHostVisible: false
    property bool networkPasswordVisible: false
    property bool networkBusy: false
    property bool networkStatusBusy: false
    property bool networkStatusPending: false
    property int networkSecretGeneration: 0
    property bool initializedVirtual: false
    property bool wlMirrorInstalled: false
    property bool mirrorActive: false

    // Apariencia de la píldora en DankBar. Los valores vienen de los ajustes del plugin.
    readonly property bool forceBarPadding: pluginData?.forceBarPadding !== false
    readonly property int barPadding: {
        const value = Number(pluginData?.barPadding ?? 6)
        if (isNaN(value))
            return 6
        return Math.max(0, Math.min(20, Math.round(value)))
    }

    property bool virtualPresent: false
    property bool virtualReady: false
    property bool virtualEnabled: false
    property string virtualLifecycle: "ERROR"
    property bool virtualSunshine: false
    property int virtualWidth: 1920
    property int virtualHeight: 1080
    property int virtualRefresh: 60000
    property string virtualCapture: "unknown"
    property string virtualAudioMode: "local"
    property var virtualModes: []

    property bool networkReady: false
    property bool networkEnabled: false
    property bool privateLanActive: false
    property string networkMode: "auto"
    property string networkEffectiveMode: "stopped"
    property string networkState: "STOPPED"
    property string networkBand: ""
    property string networkChannel: ""
    property string networkInternet: "unavailable"
    property int networkClients: 0
    property string networkHostAddress: ""
    property string networkPrivateSsid: ""
    property string networkPrivatePassword: ""
    readonly property string networkSystemHelper: "/usr/local/libexec/monitor-menu-network"
    readonly property string processNamespace: "monitorMenu."
        + Date.now().toString(36) + "." + Math.random().toString(36).slice(2)
    readonly property bool virtualInteractive: virtualPresent
        && virtualEnabled
        && virtualLifecycle === "ACTIVE"
        && !busy
    readonly property bool virtualTransitioning: virtualLifecycle === "CREATING"
        || virtualLifecycle === "DESTROYING"
    readonly property bool virtualControlsVisible: virtualReady || virtualPresent

    function runCommand(id, command, callback, debounceMs, timeoutMs) {
        Proc.runCommand(
            processNamespace + "." + id,
            command,
            callback,
            debounceMs,
            timeoutMs,
            root
        )
    }

    readonly property string mirrorHelperPath: pluginService
        ? pluginService.getPluginPath(pluginId) + "/mirror-helper.sh"
        : ""

    readonly property string virtualHelperPath: pluginService
        ? pluginService.getPluginPath(pluginId) + "/virtual-monitor-helper.sh"
        : ""

    readonly property var physicalOutputs: {
        const result = []
        for (let i = 0; i < outputs.length; ++i) {
            if (!root.isVirtualName(outputs[i].name))
                result.push(outputs[i])
        }
        return result
    }

    readonly property bool hasSecondaryOutput: physicalOutputs.length > 1 || virtualPresent
    readonly property bool canConfigureSecondary: hasSecondaryOutput || virtualReady

    readonly property int enabledSecondaryCount: {
        let count = 0
        for (let i = 0; i < physicalOutputs.length; ++i) {
            if (physicalOutputs[i].name !== primaryOutput && physicalOutputs[i].enabled)
                count++
        }
        if (virtualEnabled)
            count++
        return count
    }

    readonly property string currentMode: {
        if (mirrorActive)
            return "Duplicar"
        if (enabledSecondaryCount === 0)
            return "Solo principal"
        return "Extender"
    }

    function isVirtualName(name) {
        return name === virtualOutput || (name && name.indexOf("Virtual-") === 0)
    }

    function updatePrimaryOutput() {
        const physical = []
        for (let i = 0; i < outputs.length; ++i) {
            if (!isVirtualName(outputs[i].name))
                physical.push(outputs[i])
        }
        if (physical.length === 0)
            return

        // Prioridad: panel interno encendido → cualquier panel interno → primera salida encendida.
        for (let i = 0; i < physical.length; ++i) {
            if (physical[i].enabled && physical[i].name.indexOf("eDP-") === 0) {
                primaryOutput = physical[i].name
                return
            }
        }
        for (let i = 0; i < physical.length; ++i) {
            if (physical[i].name.indexOf("eDP-") === 0) {
                primaryOutput = physical[i].name
                return
            }
        }
        for (let i = 0; i < physical.length; ++i) {
            if (physical[i].enabled) {
                primaryOutput = physical[i].name
                return
            }
        }
        primaryOutput = physical[0].name
    }

    function headerDetails() {
        const count = physicalOutputs.length
        const physicalText = count === 1 ? "1 pantalla física" : count + " pantallas físicas"
        return virtualEnabled ? physicalText + " · virtual activa" : physicalText
    }

    function refreshOutputs() {
        root.runCommand(
            "monitorMenu.randr",
            ["dms", "randr", "--json"],
            (stdout, exitCode) => {
                if (exitCode !== 0) {
                    root.lastError = "No se pudo consultar las pantallas"
                    return
                }

                try {
                    const parsed = JSON.parse(stdout)
                    root.outputs = parsed.outputs || []
                    root.updatePrimaryOutput()
                    if (!root.initializedVirtual && root.primaryOutput.length > 0) {
                        root.initializedVirtual = true
                        root.initVirtual()
                    }
                    if (root.lastError === "No se pudo consultar las pantallas")
                        root.lastError = ""
                } catch (e) {
                    root.lastError = "Respuesta inválida de dms randr"
                }
            },
            100
        )
    }

    function parseStatus(stdout) {
        const status = {}
        const lines = stdout.trim().split("\n")
        for (let i = 0; i < lines.length; ++i) {
            const idx = lines[i].indexOf("=")
            if (idx <= 0)
                continue
            status[lines[i].slice(0, idx)] = lines[i].slice(idx + 1)
        }
        return status
    }

    function refreshVirtualStatus(done, processId) {
        if (!virtualHelperPath)
            return

        root.runCommand(
            processId || "monitorMenu.virtualStatus",
            ["sh", virtualHelperPath, "status"],
            (stdout, exitCode) => {
                if (exitCode !== 0) {
                    if (typeof done === "function")
                        done(false)
                    return
                }
                const s = root.parseStatus(stdout)
                root.virtualPresent = s.present === "1"
                root.virtualReady = s.managed === "1"
                root.virtualEnabled = s.enabled === "1"
                root.virtualLifecycle = s.lifecycle || "ERROR"
                root.virtualSunshine = s.sunshine === "1"
                root.virtualWidth = parseInt(s.width || "1920")
                root.virtualHeight = parseInt(s.height || "1080")
                root.virtualRefresh = parseInt(s.refresh || "60000")
                root.virtualCapture = s.capture || "unknown"
                root.virtualAudioMode = s.audio === "virtual" ? "virtual" : "local"
                if (typeof done === "function")
                    done(true, s)
            },
            100
        )
    }

    function initVirtual() {
        if (!virtualHelperPath)
            return

        root.busy = true
        root.runCommand(
            "monitorMenu.virtualInit",
            ["sh", virtualHelperPath, "init", primaryOutput],
            (stdout, exitCode) => {
                root.refreshVirtualStatus((ok, status) => {
                    if (!ok) {
                        root.busy = false
                        return
                    }
                    // La reconciliación de red tiene su propio flag y no debe
                    // bloquear controles de pantalla ya inicializados.
                    root.busy = false
                    root.runCommand(
                        "monitorMenu.networkReconcileStatus",
                        ["sudo", "-n", networkSystemHelper, "status"],
                        (networkOut, networkExit) => {
                            if (networkExit !== 0) {
                                root.networkReady = false
                                root.lastError = "Configura la red con setup-network.sh"
                                return
                            }
                            const networkStatus = root.parseStatus(networkOut)
                            root.networkMode = networkStatus.mode || "auto"
                            const finishInit = () => {}
                            if (status.enabled === "1")
                                root.startNetwork(finishInit)
                            else
                                root.stopNetwork(finishInit)
                        },
                        0,
                        10000
                    )
                }, "monitorMenu.virtualReconcile")
                root.refreshOutputs()
            },
            0,
            25000
        )
    }

    function closePrivateLan() {
        root.networkSecretGeneration++
        root.privateLanExpanded = false
        root.networkHostVisible = false
        root.networkPasswordVisible = false
        root.networkPrivatePassword = ""
    }

    function networkModeLabel(mode) {
        if (mode === "current") return "Red actual"
        if (mode === "bypass") return "Bypass"
        return "Automático"
    }

    function networkDetail() {
        if (!networkReady)
            return "Ejecuta setup-network.sh"
        if (!networkEnabled)
            return "Se activará con el monitor virtual"
        if (networkState === "CONNECTING")
            return "Adaptándose a la nueva red"
        if (networkEffectiveMode === "current")
            return "Usando la red disponible"
        if (privateLanActive)
            return "LAN privada activa"
        return "Preparando red"
    }

    function privateLanDetail() {
        let text = networkPrivateSsid || "LAN privada"
        if (networkBand)
            text += " · " + networkBand + " GHz"
        if (networkChannel)
            text += " · canal " + networkChannel
        text += " · " + networkClients + (networkClients === 1 ? " dispositivo" : " dispositivos")
        if (networkInternet === "shared")
            text += " · Internet"
        return text
    }

    function hiddenValue(value, visible) {
        if (!visible)
            return "••••••••"
        return value || "No disponible"
    }

    function refreshNetworkStatus(done) {
        if (networkStatusBusy) {
            root.networkStatusPending = true
            if (typeof done === "function")
                done(false)
            return
        }
        root.networkStatusBusy = true
        root.runCommand(
            "monitorMenu.networkStatus",
            ["sudo", "-n", networkSystemHelper, "status"],
            (stdout, exitCode) => {
                root.networkStatusBusy = false
                const refreshAgain = root.networkStatusPending
                root.networkStatusPending = false
                if (exitCode !== 0) {
                    root.networkReady = false
                    root.networkEnabled = false
                    root.privateLanActive = false
                    root.networkEffectiveMode = "stopped"
                    root.closePrivateLan()
                    if (typeof done === "function") done(false)
                    if (refreshAgain) root.refreshNetworkStatus()
                    return
                }
                const s = root.parseStatus(stdout)
                root.networkReady = true
                root.networkEnabled = s.enabled === "1"
                root.privateLanActive = s.lan_active === "1"
                root.networkMode = s.mode || "auto"
                root.networkEffectiveMode = s.effective_mode || "stopped"
                root.networkState = s.state || "STOPPED"
                root.networkBand = s.band || ""
                root.networkChannel = s.channel || ""
                root.networkInternet = s.internet || "unavailable"
                root.networkClients = parseInt(s.clients || "0")
                root.networkPrivateSsid = s.ssid || ""
                if (!root.privateLanActive) {
                    root.closePrivateLan()
                    root.networkHostAddress = ""
                }
                if (typeof done === "function") done(true)
                if (refreshAgain) root.refreshNetworkStatus()
            },
            100
        )
    }

    function runNetwork(action, mode, done) {
        if (networkBusy) {
            if (typeof done === "function") done(false)
            return
        }
        root.networkBusy = true
        const args = ["sudo", "-n", networkSystemHelper, action]
        if (mode)
            args.push(mode)
        root.runCommand(
            "monitorMenu.networkAction",
            args,
            (stdout, exitCode) => {
                root.networkBusy = false
                root.refreshNetworkStatus()
                if (typeof done === "function") done(exitCode === 0)
            },
            0,
            15000
        )
    }

    function setNetworkMode(mode) {
        if (mode !== "auto" && mode !== "current" && mode !== "bypass")
            return
        root.lastError = ""
        root.runNetwork(root.virtualEnabled ? "start" : "configure", mode, ok => {
            if (!ok) {
                root.lastError = "No se pudo aplicar el modo de red"
                return
            }
            root.networkMode = mode
            root.networkExpanded = false
        })
    }

    function startNetwork(done) {
        root.runNetwork("start", root.networkMode, ok => {
            if (!ok)
                root.lastError = "Configura la red con setup-network.sh"
            if (typeof done === "function") done(ok)
        })
    }

    function stopNetwork(done) {
        const cleanupExpected = root.networkEnabled
        root.runNetwork("stop", "", ok => {
            if (!ok && cleanupExpected)
                root.lastError = "No se pudo limpiar la red privada"
            if (typeof done === "function")
                done(ok || (!root.networkReady && !cleanupExpected))
        })
    }

    function fetchNetworkSecret(field, done) {
        root.runCommand(
            "monitorMenu.networkSecret." + field,
            ["sudo", "-n", networkSystemHelper, "secret", field],
            (stdout, exitCode) => {
                const value = exitCode === 0 ? stdout.trim() : ""
                if (typeof done === "function") done(exitCode === 0, value)
            },
            100
        )
    }

    function refreshVirtualModes() {
        if (!virtualHelperPath)
            return

        root.runCommand(
            "monitorMenu.virtualModes",
            ["sh", virtualHelperPath, "modes"],
            (stdout, exitCode) => {
                if (exitCode !== 0)
                    return
                const modes = []
                const lines = stdout.trim().split("\n")
                for (let i = 0; i < lines.length; ++i) {
                    if (!lines[i])
                        continue
                    const parts = lines[i].split("|")
                    const mode = parts[0] || ""
                    const label = parts[1] || mode
                    const match = mode.match(/^(\d+)x(\d+)@([0-9.]+)$/)
                    if (!match)
                        continue
                    modes.push({
                        mode: mode,
                        label: label,
                        width: parseInt(match[1]),
                        height: parseInt(match[2]),
                        refresh: Math.round(parseFloat(match[3]) * 1000)
                    })
                }
                root.virtualModes = modes
            },
            100
        )
    }

    function checkWlMirror() {
        root.runCommand(
            "monitorMenu.wlMirrorCheck",
            ["sh", "-c", "command -v wl-mirror >/dev/null 2>&1"],
            (stdout, exitCode) => root.wlMirrorInstalled = (exitCode === 0),
            250
        )
    }

    function checkMirrorState() {
        if (!mirrorHelperPath)
            return

        root.runCommand(
            "monitorMenu.mirrorStatus",
            ["sh", mirrorHelperPath, "status"],
            (stdout, exitCode) => {
                root.mirrorActive = (exitCode === 0 && stdout.trim() === "active")
            },
            100
        )
    }

    function friendlyName(name) {
        if (name === primaryOutput || name.indexOf("eDP-") === 0)
            return "Pantalla integrada"
        return "Pantalla externa"
    }

    function hz(refresh) {
        return Math.round((refresh || 0) / 1000)
    }

    function virtualDetail() {
        if (!virtualReady)
            return "Ejecuta setup-vkms.sh"
        if (virtualLifecycle === "CREATING")
            return "Creando " + virtualOutput + "…"
        if (virtualLifecycle === "DESTROYING")
            return "Destruyendo " + virtualOutput + "…"
        if (!virtualPresent)
            return "Apagado · salida VKMS desconectada"
        if (virtualEnabled && !virtualSunshine)
            return virtualOutput + " · " + virtualWidth + "×" + virtualHeight + " · sin Sunshine"
        if (virtualEnabled && virtualCapture === "wrong")
            return virtualOutput + " · captura incorrecta"
        return virtualOutput + " · " + virtualWidth + "×" + virtualHeight
               + " · " + hz(virtualRefresh) + " Hz · audio "
               + (virtualAudioMode === "virtual" ? "Virtual" : "Local")
    }

    function stopMirror(done) {
        if (!mirrorHelperPath) {
            root.mirrorActive = false
            if (done) done()
            return
        }

        root.runCommand(
            "monitorMenu.mirrorStop",
            ["sh", mirrorHelperPath, "stop"],
            (stdout, exitCode) => {
                root.mirrorActive = false
                if (done) done()
            }
        )
    }

    function toggleOutput(output) {
        if (!output || output.name === primaryOutput || isVirtualName(output.name) || busy)
            return

        root.busy = true
        root.lastError = ""

        const performToggle = () => {
            root.runCommand(
                "monitorMenu.outputToggle",
                ["niri", "msg", "output", output.name, output.enabled ? "off" : "on"],
                (stdout, exitCode) => {
                    root.busy = false
                    if (exitCode !== 0)
                        root.lastError = "No se pudo cambiar " + output.name
                    refreshAfterAction.restart()
                }
            )
        }

        if (mirrorActive)
            stopMirror(performToggle)
        else
            performToggle()
    }

    function setVirtualMode(mode) {
        if (!virtualInteractive || !virtualHelperPath)
            return

        root.busy = true
        root.lastError = ""

        root.runCommand(
            "monitorMenu.virtualModeSet",
            ["sh", virtualHelperPath, "set-mode", mode, primaryOutput],
            (stdout, exitCode) => {
                root.busy = false
                if (exitCode === 27)
                    root.lastError = "Esa resolución no está disponible en VKMS"
                else if (exitCode !== 0)
                    root.lastError = "No se pudo cambiar la resolución virtual"
                else
                    root.resolutionExpanded = false
                refreshAfterAction.restart()
            },
            0,
            25000
        )
    }

    function setVirtualAudio(mode) {
        if (!virtualInteractive || !virtualHelperPath)
            return
        if (mode !== "local" && mode !== "virtual")
            return

        root.busy = true
        root.lastError = ""

        root.runCommand(
            "monitorMenu.virtualAudioSet",
            ["sh", virtualHelperPath, "set-audio", mode],
            (stdout, exitCode) => {
                root.busy = false
                if (exitCode === 29)
                    root.lastError = "Modo de audio inválido"
                else if (exitCode === 127)
                    root.lastError = "No se encontró Sunshine"
                else if (exitCode !== 0)
                    root.lastError = "No se pudo cambiar el audio virtual"
                else
                    root.audioExpanded = false
                refreshAfterAction.restart()
            },
            0,
            25000
        )
    }

    function toggleVirtual() {
        if (busy || networkBusy || virtualTransitioning)
            return

        if (!virtualReady) {
            root.lastError = "Configura VKMS con setup-vkms.sh"
            return
        }

        const turningOn = !virtualEnabled
        root.busy = true
        root.lastError = ""

        const changeVirtual = () => {
            root.runCommand(
                "monitorMenu.virtualToggle",
                ["sh", virtualHelperPath, turningOn ? "start" : "stop", primaryOutput],
                (stdout, exitCode) => {
                    if (exitCode === 31)
                        root.lastError = "Configura VKMS con setup-vkms.sh"
                    else if (exitCode >= 32 && exitCode <= 35)
                        root.lastError = "No se pudo crear o destruir VKMS"
                    else if (exitCode === 127)
                        root.lastError = "No se encontró Sunshine"
                    else if (exitCode !== 0)
                        root.lastError = "No se pudo cambiar el monitor virtual"

                    const finishChange = () => {
                        root.busy = false
                        refreshAfterAction.restart()
                        if (exitCode === 0 && turningOn)
                            root.startNetwork()
                    }
                    root.refreshVirtualStatus(finishChange, "monitorMenu.virtualToggleRefresh")
                },
                0,
                25000
            )
        }

        if (turningOn)
            changeVirtual()
        else {
            root.stopNetwork(ok => {
                if (ok) {
                    changeVirtual()
                    return
                }
                root.busy = false
                root.lastError = "No se pudo limpiar la red privada"
                refreshAfterAction.restart()
            })
        }
    }

    function onlyPrimary() {
        if (busy || networkBusy || virtualTransitioning)
            return

        root.busy = true
        root.lastError = ""

        stopMirror(() => {
            for (let i = 0; i < physicalOutputs.length; ++i) {
                const output = physicalOutputs[i]
                if (output.name !== primaryOutput && output.enabled)
                    Quickshell.execDetached(["niri", "msg", "output", output.name, "off"])
            }

            const finish = () => {
                root.busy = false
                root.modesExpanded = false
                refreshAfterAction.restart()
            }

            if ((virtualEnabled || virtualPresent) && virtualHelperPath) {
                root.stopNetwork(ok => {
                    if (!ok) {
                        finish()
                        return
                    }
                    root.runCommand(
                        "monitorMenu.modeVirtualStop",
                        ["sh", virtualHelperPath, "stop"],
                        (stdout, exitCode) => {
                            if (exitCode !== 0)
                                root.lastError = "No se pudo apagar el monitor virtual"
                            finish()
                        },
                        0,
                        15000
                    )
                })
            } else {
                root.stopNetwork(finish)
            }
        })
    }

    function extendAll() {
        if (busy || networkBusy || virtualTransitioning)
            return

        root.busy = true
        root.lastError = ""

        stopMirror(() => {
            for (let i = 0; i < physicalOutputs.length; ++i) {
                const output = physicalOutputs[i]
                if (!output.enabled)
                    Quickshell.execDetached(["niri", "msg", "output", output.name, "on"])
            }

            const finish = () => {
                root.busy = false
                root.modesExpanded = false
                refreshAfterAction.restart()
            }

            if (virtualReady && !virtualEnabled && virtualHelperPath) {
                root.runCommand(
                    "monitorMenu.modeVirtualStart",
                    ["sh", virtualHelperPath, "start", primaryOutput],
                    (stdout, exitCode) => {
                        if (exitCode === 31)
                            root.lastError = "Configura VKMS con setup-vkms.sh"
                        else if (exitCode >= 32 && exitCode <= 35)
                            root.lastError = "No se pudo crear VKMS"
                        else if (exitCode === 127)
                            root.lastError = "No se encontró Sunshine"
                        else if (exitCode !== 0)
                            root.lastError = "No se pudo encender el monitor virtual"
                        finish()
                        if (exitCode === 0)
                            root.startNetwork()
                    },
                    0,
                    25000
                )
            } else {
                if (virtualEnabled)
                    root.startNetwork()
                finish()
            }
        })
    }

    function duplicatePrimary() {
        if (busy || networkBusy || virtualTransitioning || !canConfigureSecondary)
            return

        if (!wlMirrorInstalled) {
            root.lastError = "Duplicar requiere wl-mirror"
            return
        }

        if (!mirrorHelperPath) {
            root.lastError = "No se encontró el helper de duplicación"
            return
        }

        const targets = []
        for (let i = 0; i < physicalOutputs.length; ++i) {
            if (physicalOutputs[i].name !== primaryOutput)
                targets.push(physicalOutputs[i].name)
        }
        if (virtualPresent || virtualReady)
            targets.push(virtualOutput)

        if (targets.length === 0)
            return

        root.busy = true
        root.lastError = ""

        const startMirror = () => {
            const args = ["sh", mirrorHelperPath, "start", primaryOutput]
            for (let i = 0; i < targets.length; ++i)
                args.push(targets[i])

            root.runCommand(
                "monitorMenu.mirrorStart",
                args,
                (stdout, exitCode) => {
                    root.busy = false

                    if (exitCode === 0) {
                        root.mirrorActive = true
                        root.modesExpanded = false
                    } else if (exitCode === 127) {
                        root.wlMirrorInstalled = false
                        root.lastError = "Duplicar requiere wl-mirror"
                    } else {
                        root.lastError = "No se pudo iniciar la duplicación"
                    }

                    refreshAfterAction.restart()
                },
                0,
                15000
            )
        }

        if (virtualReady && !virtualEnabled && virtualHelperPath) {
            root.runCommand(
                "monitorMenu.duplicateVirtualStart",
                ["sh", virtualHelperPath, "start", primaryOutput],
                (stdout, exitCode) => {
                    if (exitCode !== 0) {
                        root.busy = false
                        if (exitCode === 31)
                            root.lastError = "Configura VKMS con setup-vkms.sh"
                        else if (exitCode >= 32 && exitCode <= 35)
                            root.lastError = "No se pudo crear VKMS"
                        else if (exitCode === 127)
                            root.lastError = "No se encontró Sunshine"
                        else
                            root.lastError = "No se pudo encender el monitor virtual"
                        refreshAfterAction.restart()
                        return
                    }
                    root.startNetwork()
                    startMirror()
                },
                0,
                25000
            )
        } else {
            if (virtualEnabled)
                root.startNetwork()
            startMirror()
        }
    }

    function refreshVisibleState() {
        root.refreshOutputs()
        root.checkMirrorState()
        root.refreshVirtualStatus()
        root.refreshVirtualModes()
        root.refreshNetworkStatus()
    }

    Component.onCompleted: {
        refreshOutputs()
        refreshVirtualStatus()
        refreshVirtualModes()
        checkWlMirror()
        checkMirrorState()
    }

    Timer {
        id: refreshAfterAction
        interval: 750
        repeat: false
        onTriggered: {
            root.refreshOutputs()
            root.checkMirrorState()
            root.refreshVirtualStatus()
            root.refreshVirtualModes()
            root.refreshNetworkStatus()
        }
    }

    popoutWidth: 420
    popoutHeight: Math.min(
        760,
        165
        + root.physicalOutputs.length * 66
        + 66
        + (root.virtualControlsVisible ? 56 : 0)
        + (root.virtualInteractive && root.resolutionExpanded ? Math.max(1, root.virtualModes.length) * 46 : 0)
        + (root.virtualControlsVisible ? 56 : 0)
        + (root.virtualInteractive && root.audioExpanded ? 92 : 0)
        + (root.virtualPresent ? 66 : 0)
        + (root.virtualPresent && root.networkExpanded ? 138 : 0)
        + (root.virtualPresent && root.privateLanActive ? 66 : 0)
        + (root.virtualPresent && root.privateLanActive && root.privateLanExpanded ? 92 : 0)
        + (root.canConfigureSecondary ? 56 : 0)
        + (root.canConfigureSecondary && root.modesExpanded ? 144 : 0)
    )

    horizontalBarPill: Component {
        Components.MonitorBarPill {
            vertical: false
            widgetThickness: root.widgetThickness
            widgetIconSize: root.iconSize
            active: root.mirrorActive || root.virtualEnabled
            forcePadding: root.forceBarPadding
            barPadding: root.barPadding
        }
    }

    verticalBarPill: Component {
        Components.MonitorBarPill {
            vertical: true
            widgetThickness: root.widgetThickness
            widgetIconSize: root.iconSize
            active: root.mirrorActive || root.virtualEnabled
            forcePadding: root.forceBarPadding
            barPadding: root.barPadding
        }
    }

    popoutContent: Component {
        Components.MonitorMenuPopout {
            backend: root
        }
    }
}
