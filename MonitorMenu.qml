import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

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
                if (exitCode !== 0) {
                    root.networkReady = false
                    root.networkEnabled = false
                    root.privateLanActive = false
                    root.networkEffectiveMode = "stopped"
                    root.closePrivateLan()
                    if (typeof done === "function") done(false)
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
            if (typeof done === "function") done(ok)
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
            return "Apagado · VKMS descargado"
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
        if (busy || !virtualPresent || !virtualHelperPath)
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
        if (busy || !virtualPresent || !virtualHelperPath)
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
        if (busy)
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

                    if (exitCode === 0 && turningOn) {
                        root.busy = false
                        refreshAfterAction.restart()
                        root.startNetwork()
                    } else {
                        root.busy = false
                        refreshAfterAction.restart()
                    }
                },
                0,
                25000
            )
        }

        if (turningOn)
            changeVirtual()
        else
            root.stopNetwork(changeVirtual)
    }

    function onlyPrimary() {
        if (busy)
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
                root.stopNetwork(() => {
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
        if (busy)
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
        if (busy || !canConfigureSecondary)
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
        StyledRect {
            // Use PluginComponent dimensions directly. The loaded pill should not depend
            // on its Loader parent exposing widgetThickness.
            readonly property real innerPadding: root.forceBarPadding ? root.barPadding : 0
            implicitWidth: Math.max(root.widgetThickness, root.iconSize + innerPadding * 2)
            width: implicitWidth
            height: root.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                anchors.centerIn: parent
                name: "desktop_windows"
                size: root.iconSize
                color: (root.mirrorActive || root.virtualEnabled) ? Theme.primary : Theme.surfaceText
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            readonly property real innerPadding: root.forceBarPadding ? root.barPadding : 0
            width: root.widgetThickness
            implicitHeight: Math.max(root.widgetThickness, root.iconSize + innerPadding * 2)
            height: implicitHeight
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                anchors.centerIn: parent
                name: "desktop_windows"
                size: root.iconSize
                color: (root.mirrorActive || root.virtualEnabled) ? Theme.primary : Theme.surfaceText
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Pantallas"
            detailsText: root.headerDetails()

            property string copiedField: ""
            Component.onDestruction: root.closePrivateLan()

            Connections {
                target: popout.parentPopout
                enabled: popout.parentPopout !== null

                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout.shouldBeVisible)
                        root.refreshVisibleState()
                }
            }

            // Keep transient network and display state current only while the menu is open.
            Timer {
                interval: 5000
                repeat: true
                running: popout.parentPopout?.shouldBeVisible ?? false
                onTriggered: root.refreshVisibleState()
            }

            TextInput {
                id: clipboardBuffer
                width: 1
                height: 1
                opacity: 0
                text: ""
            }

            Timer {
                id: copyFeedbackTimer
                interval: 1400
                repeat: false
                onTriggered: {
                    popout.copiedField = ""
                    clipboardBuffer.text = ""
                    if (!root.networkPasswordVisible)
                        root.networkPrivatePassword = ""
                }
            }

            function copyValue(value, field) {
                if (!value)
                    return
                clipboardBuffer.text = value
                clipboardBuffer.selectAll()
                clipboardBuffer.copy()
                clipboardBuffer.deselect()
                popout.copiedField = field
                copyFeedbackTimer.restart()
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.physicalOutputs

                    delegate: StyledRect {
                        property var outputData: modelData

                        width: parent.width
                        height: 58
                        radius: Theme.cornerRadius
                        color: outputMouse.containsMouse && outputData.name !== root.primaryOutput
                               ? Theme.surfaceContainerHighest
                               : Theme.surfaceContainerHigh

                        DankIcon {
                            id: displayIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            name: outputData.name === root.primaryOutput ? "laptop" : "monitor"
                            size: Theme.iconSize
                            color: Theme.surfaceText
                        }

                        Column {
                            anchors.left: displayIcon.right
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: stateLabel.left
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                width: parent.width
                                text: root.friendlyName(outputData.name)
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: outputData.name
                                      + (outputData.width > 0
                                         ? " · " + outputData.width + "×" + outputData.height
                                           + " · " + root.hz(outputData.refresh) + " Hz"
                                         : "")
                                      + (outputData.name === root.primaryOutput ? " · Principal" : "")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                            }
                        }

                        StyledText {
                            id: stateLabel
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            text: outputData.enabled ? "ON" : "OFF"
                            color: outputData.enabled ? Theme.primary : Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            id: outputMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: outputData.name !== root.primaryOutput && !root.busy
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.toggleOutput(outputData)
                        }
                    }
                }

                StyledRect {
                    visible: root.canConfigureSecondary
                    width: parent.width
                    height: 48
                    radius: Theme.cornerRadius
                    color: modeMouse.containsMouse
                           ? Theme.surfaceContainerHighest
                           : Theme.surfaceContainerHigh

                    DankIcon {
                        id: modeIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.mirrorActive ? "content_copy" : "view_carousel"
                        size: Theme.iconSize
                        color: Theme.surfaceText
                    }

                    StyledText {
                        anchors.left: modeIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Modo de pantalla"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            text: root.currentMode
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        DankIcon {
                            name: root.modesExpanded ? "expand_less" : "chevron_right"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    MouseArea {
                        id: modeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.modesExpanded = !root.modesExpanded
                            if (root.modesExpanded) {
                                root.resolutionExpanded = false
                                root.audioExpanded = false
                                root.networkExpanded = false
                                root.closePrivateLan()
                            }
                        }
                    }
                }

                Column {
                    visible: root.canConfigureSecondary && root.modesExpanded
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: [
                            { label: "Solo principal", icon: "laptop", action: "primary", enabled: true },
                            { label: "Duplicar", icon: "content_copy", action: "duplicate", enabled: root.wlMirrorInstalled },
                            { label: "Extender", icon: "desktop_windows", action: "extend", enabled: true }
                        ]

                        delegate: StyledRect {
                            property var modeData: modelData

                            width: parent.width
                            height: 42
                            radius: Theme.cornerRadius
                            color: modeOptionMouse.containsMouse && modeData.enabled
                                   ? Theme.surfaceContainerHighest
                                   : Theme.surfaceContainerHigh
                            opacity: modeData.enabled ? 1.0 : 0.55

                            DankIcon {
                                id: optionIcon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                name: modeData.icon
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                            }

                            StyledText {
                                anchors.left: optionIcon.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                text: modeData.label
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            StyledText {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modeData.action === "duplicate" && !root.wlMirrorInstalled
                                text: "requiere wl-mirror"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            MouseArea {
                                id: modeOptionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: modeData.enabled && !root.busy
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (modeData.action === "primary")
                                        root.onlyPrimary()
                                    else if (modeData.action === "duplicate")
                                        root.duplicatePrimary()
                                    else if (modeData.action === "extend")
                                        root.extendAll()
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: 58
                    radius: Theme.cornerRadius
                    color: virtualMouse.containsMouse && root.virtualReady
                           ? Theme.surfaceContainerHighest
                           : Theme.surfaceContainerHigh
                    opacity: root.virtualReady ? 1.0 : 0.65

                    DankIcon {
                        id: virtualIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: "cast"
                        size: Theme.iconSize
                        color: root.virtualEnabled ? Theme.primary : Theme.surfaceText
                    }

                    Column {
                        anchors.left: virtualIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: virtualState.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        StyledText {
                            width: parent.width
                            text: "Monitor virtual"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root.virtualDetail()
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }

                    StyledText {
                        id: virtualState
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.virtualEnabled ? "ON" : "OFF"
                        color: root.virtualEnabled ? Theme.primary : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        id: virtualMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.virtualReady && !root.busy
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.toggleVirtual()
                    }
                }

                StyledRect {
                    visible: root.virtualControlsVisible
                    width: parent.width
                    height: 48
                    radius: Theme.cornerRadius
                    color: resolutionMouse.containsMouse
                           ? Theme.surfaceContainerHighest
                           : Theme.surfaceContainerHigh
                    opacity: root.virtualInteractive ? 1.0 : 0.55

                    DankIcon {
                        id: resolutionIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: "aspect_ratio"
                        size: Theme.iconSize
                        color: Theme.surfaceText
                    }

                    StyledText {
                        anchors.left: resolutionIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Resolución virtual"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            text: root.virtualWidth + "×" + root.virtualHeight
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        DankIcon {
                            name: root.resolutionExpanded ? "expand_less" : "chevron_right"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    MouseArea {
                        id: resolutionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.virtualInteractive && root.virtualModes.length > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            root.resolutionExpanded = !root.resolutionExpanded
                            if (root.resolutionExpanded) {
                                root.modesExpanded = false
                                root.audioExpanded = false
                                root.networkExpanded = false
                                root.closePrivateLan()
                            }
                        }
                    }
                }

                Column {
                    visible: root.virtualInteractive && root.resolutionExpanded
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: root.virtualModes

                        delegate: StyledRect {
                            property var resolutionData: modelData
                            readonly property bool selected: root.virtualWidth === resolutionData.width
                                                             && root.virtualHeight === resolutionData.height
                                                             && Math.abs(root.virtualRefresh - resolutionData.refresh) < 1000

                            width: parent.width
                            height: 42
                            radius: Theme.cornerRadius
                            color: resolutionOptionMouse.containsMouse
                                   ? Theme.surfaceContainerHighest
                                   : Theme.surfaceContainerHigh

                            DankIcon {
                                id: resolutionCheck
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                name: selected ? "check_circle" : "radio_button_unchecked"
                                size: Theme.iconSizeSmall
                                color: selected ? Theme.primary : Theme.surfaceVariantText
                            }

                            StyledText {
                                anchors.left: resolutionCheck.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                text: resolutionData.label
                                color: selected ? Theme.primary : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            StyledText {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                text: resolutionData.width + "×" + resolutionData.height
                                      + " · " + Math.round(resolutionData.refresh / 1000) + " Hz"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            MouseArea {
                                id: resolutionOptionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !root.busy && !selected
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.setVirtualMode(resolutionData.mode)
                            }
                        }
                    }
                }


                StyledRect {
                    visible: root.virtualControlsVisible
                    width: parent.width
                    height: 48
                    radius: Theme.cornerRadius
                    color: audioMouse.containsMouse
                           ? Theme.surfaceContainerHighest
                           : Theme.surfaceContainerHigh
                    opacity: root.virtualInteractive ? 1.0 : 0.55

                    DankIcon {
                        id: audioIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.virtualAudioMode === "virtual" ? "cast_connected" : "volume_up"
                        size: Theme.iconSize
                        color: Theme.surfaceText
                    }

                    StyledText {
                        anchors.left: audioIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Audio"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            text: root.virtualAudioMode === "virtual" ? "Virtual" : "Local"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        DankIcon {
                            name: root.audioExpanded ? "expand_less" : "chevron_right"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    MouseArea {
                        id: audioMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.virtualInteractive
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            root.audioExpanded = !root.audioExpanded
                            if (root.audioExpanded) {
                                root.resolutionExpanded = false
                                root.modesExpanded = false
                                root.networkExpanded = false
                                root.closePrivateLan()
                            }
                        }
                    }
                }

                Column {
                    visible: root.virtualInteractive && root.audioExpanded
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: [
                            {
                                mode: "local",
                                label: "Local",
                                detail: "Audio solo en el equipo",
                                icon: "speaker"
                            },
                            {
                                mode: "virtual",
                                label: "Virtual",
                                detail: "Audio solo en el receptor virtual",
                                icon: "cast_connected"
                            }
                        ]

                        delegate: StyledRect {
                            property var audioData: modelData
                            readonly property bool selected: root.virtualAudioMode === audioData.mode

                            width: parent.width
                            height: 42
                            radius: Theme.cornerRadius
                            color: audioOptionMouse.containsMouse
                                   ? Theme.surfaceContainerHighest
                                   : Theme.surfaceContainerHigh

                            DankIcon {
                                id: audioCheck
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                name: selected ? "check_circle" : audioData.icon
                                size: Theme.iconSizeSmall
                                color: selected ? Theme.primary : Theme.surfaceVariantText
                            }

                            Column {
                                anchors.left: audioCheck.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                StyledText {
                                    text: audioData.label
                                    color: selected ? Theme.primary : Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                StyledText {
                                    text: audioData.detail
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            MouseArea {
                                id: audioOptionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !root.busy && !selected
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.setVirtualAudio(audioData.mode)
                            }
                        }
                    }
                }

                StyledRect {
                    visible: root.virtualPresent
                    width: parent.width
                    height: 58
                    radius: Theme.cornerRadius
                    color: networkMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    opacity: root.networkBusy ? 0.65 : 1.0

                    DankIcon {
                        id: networkIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.privateLanActive ? "lan" : "wifi"
                        size: Theme.iconSize
                        color: root.networkEnabled ? Theme.primary : Theme.surfaceText
                    }

                    Column {
                        anchors.left: networkIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: networkModeRow.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        StyledText {
                            width: parent.width
                            text: "Modo de red"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root.networkDetail()
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: networkModeRow
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            text: root.networkModeLabel(root.networkMode)
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        DankIcon {
                            name: root.networkExpanded ? "expand_less" : "chevron_right"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    MouseArea {
                        id: networkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.busy && !root.networkBusy
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            root.networkExpanded = !root.networkExpanded
                            if (root.networkExpanded) {
                                root.modesExpanded = false
                                root.resolutionExpanded = false
                                root.audioExpanded = false
                                root.closePrivateLan()
                            }
                        }
                    }
                }

                Column {
                    visible: root.virtualPresent && root.networkExpanded
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: [
                            { mode: "auto", label: "Automático", detail: "Se adapta a la red disponible", icon: "sync" },
                            { mode: "current", label: "Red actual", detail: "Usa la red donde ya estás conectado", icon: "wifi" },
                            { mode: "bypass", label: "Bypass", detail: "Crea una conexión privada directa", icon: "lan" }
                        ]

                        delegate: StyledRect {
                            property var networkData: modelData
                            readonly property bool selected: root.networkMode === networkData.mode
                            width: parent.width
                            height: 42
                            radius: Theme.cornerRadius
                            color: networkOptionMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            opacity: root.networkReady ? 1.0 : 0.65

                            DankIcon {
                                id: networkCheck
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                name: selected ? "check_circle" : networkData.icon
                                size: Theme.iconSizeSmall
                                color: selected ? Theme.primary : Theme.surfaceVariantText
                            }

                            Column {
                                anchors.left: networkCheck.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: networkData.label
                                    color: selected ? Theme.primary : Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                StyledText {
                                    text: networkData.detail
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            MouseArea {
                                id: networkOptionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.networkReady && !root.busy && !root.networkBusy && !selected
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.setNetworkMode(networkData.mode)
                            }
                        }
                    }
                }

                StyledRect {
                    visible: root.virtualPresent && root.privateLanActive
                    width: parent.width
                    height: 58
                    radius: Theme.cornerRadius
                    color: privateLanMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    DankIcon {
                        id: privateLanIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: "lan"
                        size: Theme.iconSize
                        color: Theme.primary
                    }

                    Column {
                        anchors.left: privateLanIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: privateLanRight.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        StyledText {
                            text: "LAN privada"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                        }
                        StyledText {
                            width: parent.width
                            text: root.privateLanDetail()
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: privateLanRight
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS
                        StyledText {
                            text: "Activa"
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        DankIcon {
                            name: root.privateLanExpanded ? "expand_less" : "chevron_right"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    MouseArea {
                        id: privateLanMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.privateLanExpanded = !root.privateLanExpanded
                            root.networkExpanded = false
                            if (!root.privateLanExpanded) {
                                root.closePrivateLan()
                            }
                        }
                    }
                }

                Column {
                    visible: root.virtualPresent && root.privateLanActive && root.privateLanExpanded
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: [
                            { field: "host", label: "Host", icon: "lan" },
                            { field: "password", label: "Clave", icon: "key" }
                        ]

                        delegate: StyledRect {
                            property var secretData: modelData
                            readonly property bool revealed: secretData.field === "host"
                                ? root.networkHostVisible : root.networkPasswordVisible
                            readonly property string value: secretData.field === "host"
                                ? root.networkHostAddress : root.networkPrivatePassword
                            width: parent.width
                            height: 42
                            radius: Theme.cornerRadius
                            color: secretMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            DankIcon {
                                id: secretIcon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                name: secretData.icon
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                anchors.left: secretIcon.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                text: secretData.label
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS
                                StyledText {
                                    text: popout.copiedField === secretData.field
                                        ? (secretData.field === "host" ? "Copiado" : "Copiada")
                                        : root.hiddenValue(value, revealed)
                                    color: (revealed || popout.copiedField === secretData.field)
                                        ? Theme.primary : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                DankIcon {
                                    name: popout.copiedField === secretData.field
                                        ? "check" : (revealed ? "visibility_off" : "visibility")
                                    size: Theme.iconSizeSmall
                                    color: popout.copiedField === secretData.field ? Theme.primary : Theme.surfaceVariantText
                                }
                            }

                            MouseArea {
                                id: secretMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    const requestedField = secretData.field
                                    const requestedButton = mouse.button
                                    const generation = root.networkSecretGeneration
                                    root.fetchNetworkSecret(requestedField, (ok, freshValue) => {
                                        if (!ok || generation !== root.networkSecretGeneration
                                                || !root.privateLanActive || !root.privateLanExpanded)
                                            return
                                        if (requestedButton === Qt.RightButton) {
                                            popout.copyValue(freshValue, requestedField)
                                            return
                                        }
                                        if (requestedField === "host") {
                                            root.networkHostAddress = freshValue
                                            root.networkHostVisible = !root.networkHostVisible
                                        } else {
                                            root.networkPrivatePassword = freshValue
                                            root.networkPasswordVisible = !root.networkPasswordVisible
                                            if (!root.networkPasswordVisible)
                                                root.networkPrivatePassword = ""
                                        }
                                    })
                                }
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.lastError.length > 0
                    width: parent.width
                    text: root.lastError
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
