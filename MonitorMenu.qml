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
    property bool virtualEnabled: false
    property bool virtualSunshine: false
    property int virtualWidth: 1920
    property int virtualHeight: 1080
    property int virtualRefresh: 60000
    property string virtualCapture: "unknown"
    property string virtualAudioMode: "local"
    property var virtualModes: []

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

    readonly property int enabledSecondaryCount: {
        let count = 0
        for (let i = 0; i < physicalOutputs.length; ++i) {
            if (physicalOutputs[i].name !== primaryOutput && physicalOutputs[i].enabled)
                count++
        }
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
        Proc.runCommand(
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

    function refreshVirtualStatus() {
        if (!virtualHelperPath)
            return

        Proc.runCommand(
            "monitorMenu.virtualStatus",
            ["sh", virtualHelperPath, "status"],
            (stdout, exitCode) => {
                if (exitCode !== 0)
                    return
                const s = root.parseStatus(stdout)
                root.virtualPresent = s.present === "1"
                root.virtualEnabled = s.enabled === "1"
                root.virtualSunshine = s.sunshine === "1"
                root.virtualWidth = parseInt(s.width || "1920")
                root.virtualHeight = parseInt(s.height || "1080")
                root.virtualRefresh = parseInt(s.refresh || "60000")
                root.virtualCapture = s.capture || "unknown"
                root.virtualAudioMode = s.audio === "virtual" ? "virtual" : "local"
            },
            100
        )
    }

    function initVirtual() {
        if (!virtualHelperPath)
            return

        Proc.runCommand(
            "monitorMenu.virtualInit",
            ["sh", virtualHelperPath, "init", primaryOutput],
            (stdout, exitCode) => {
                root.refreshVirtualStatus()
                root.refreshOutputs()
            }
        )
    }

    function refreshVirtualModes() {
        if (!virtualHelperPath)
            return

        Proc.runCommand(
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
        Proc.runCommand(
            "monitorMenu.wlMirrorCheck",
            ["sh", "-c", "command -v wl-mirror >/dev/null 2>&1"],
            (stdout, exitCode) => root.wlMirrorInstalled = (exitCode === 0),
            250
        )
    }

    function checkMirrorState() {
        if (!mirrorHelperPath)
            return

        Proc.runCommand(
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
        if (!virtualPresent)
            return "VKMS no cargado"
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

        Proc.runCommand(
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
            Proc.runCommand(
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

        Proc.runCommand(
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
            }
        )
    }

    function setVirtualAudio(mode) {
        if (busy || !virtualPresent || !virtualHelperPath)
            return
        if (mode !== "local" && mode !== "virtual")
            return

        root.busy = true
        root.lastError = ""

        Proc.runCommand(
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
            }
        )
    }

    function toggleVirtual() {
        if (busy)
            return

        if (!virtualPresent) {
            root.lastError = "VKMS no está cargado; ejecuta setup-vkms.sh una vez"
            return
        }

        root.busy = true
        root.lastError = ""

        Proc.runCommand(
            "monitorMenu.virtualToggle",
            ["sh", virtualHelperPath, virtualEnabled ? "stop" : "start", primaryOutput],
            (stdout, exitCode) => {
                root.busy = false
                if (exitCode === 20)
                    root.lastError = "No se encontró " + virtualOutput + " (VKMS)"
                else if (exitCode === 127)
                    root.lastError = "No se encontró Sunshine"
                else if (exitCode !== 0)
                    root.lastError = "No se pudo cambiar el monitor virtual"
                refreshAfterAction.restart()
            }
        )
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
            root.modesExpanded = false
            refreshAfterAction.restart()
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
            root.modesExpanded = false
            refreshAfterAction.restart()
        })
    }

    function duplicatePrimary() {
        if (busy || physicalOutputs.length < 2)
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

        if (targets.length === 0)
            return

        root.busy = true
        root.lastError = ""

        const args = ["sh", mirrorHelperPath, "start", primaryOutput]
        for (let i = 0; i < targets.length; ++i)
            args.push(targets[i])

        Proc.runCommand(
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
            }
        )
    }

    Component.onCompleted: {
        refreshOutputs()
        refreshVirtualStatus()
        refreshVirtualModes()
        checkWlMirror()
        checkMirrorState()
    }

    // Estado/hotplug sin reiniciar DMS.
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.refreshOutputs()
            root.checkMirrorState()
            root.refreshVirtualStatus()
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: {
            root.checkWlMirror()
            root.refreshVirtualModes()
        }
    }

    Timer {
        id: refreshAfterAction
        interval: 750
        repeat: false
        onTriggered: {
            root.busy = false
            root.refreshOutputs()
            root.checkMirrorState()
            root.refreshVirtualStatus()
            root.refreshVirtualModes()
        }
    }

    popoutWidth: 420
    popoutHeight: Math.min(
        760,
        165
        + root.physicalOutputs.length * 66
        + 66
        + (root.virtualPresent ? 56 : 0)
        + (root.virtualPresent && root.resolutionExpanded ? Math.max(1, root.virtualModes.length) * 46 : 0)
        + (root.virtualPresent ? 56 : 0)
        + (root.virtualPresent && root.audioExpanded ? 92 : 0)
        + (root.physicalOutputs.length > 1 ? 56 : 0)
        + (root.physicalOutputs.length > 1 && root.modesExpanded ? 144 : 0)
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
            headerText: "Pantallas"
            detailsText: root.headerDetails()

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
                    visible: root.physicalOutputs.length > 1
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
                            }
                        }
                    }
                }

                Column {
                    visible: root.physicalOutputs.length > 1 && root.modesExpanded
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
                    color: virtualMouse.containsMouse && root.virtualPresent
                           ? Theme.surfaceContainerHighest
                           : Theme.surfaceContainerHigh
                    opacity: root.virtualPresent ? 1.0 : 0.65

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
                        enabled: root.virtualPresent && !root.busy
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.toggleVirtual()
                    }
                }

                StyledRect {
                    visible: root.virtualPresent
                    width: parent.width
                    height: 48
                    radius: Theme.cornerRadius
                    color: resolutionMouse.containsMouse
                           ? Theme.surfaceContainerHighest
                           : Theme.surfaceContainerHigh
                    opacity: root.busy ? 0.65 : 1.0

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
                        enabled: !root.busy && root.virtualModes.length > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            root.resolutionExpanded = !root.resolutionExpanded
                            if (root.resolutionExpanded) {
                                root.modesExpanded = false
                                root.audioExpanded = false
                            }
                        }
                    }
                }

                Column {
                    visible: root.virtualPresent && root.resolutionExpanded
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
                    visible: root.virtualPresent
                    width: parent.width
                    height: 48
                    radius: Theme.cornerRadius
                    color: audioMouse.containsMouse
                           ? Theme.surfaceContainerHighest
                           : Theme.surfaceContainerHigh
                    opacity: root.busy ? 0.65 : 1.0

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
                        enabled: !root.busy
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            root.audioExpanded = !root.audioExpanded
                            if (root.audioExpanded) {
                                root.resolutionExpanded = false
                                root.modesExpanded = false
                            }
                        }
                    }
                }

                Column {
                    visible: root.virtualPresent && root.audioExpanded
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
