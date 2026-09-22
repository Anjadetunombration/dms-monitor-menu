import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PopoutComponent {
    id: popout

    required property var backend
    property string copiedField: ""

    headerText: "Pantallas"
    detailsText: backend.headerDetails()

    Component.onDestruction: backend.closePrivateLan()

    Connections {
        target: popout.parentPopout
        enabled: popout.parentPopout !== null

        function onShouldBeVisibleChanged() {
            if (popout.parentPopout.shouldBeVisible)
                popout.backend.refreshVisibleState()
        }
    }

    // Keep transient network and display state current only while the menu is open.
    Timer {
        interval: 5000
        repeat: true
        running: popout.parentPopout?.shouldBeVisible ?? false
        onTriggered: popout.backend.refreshVisibleState()
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
            if (!popout.backend.networkPasswordVisible)
                popout.backend.networkPrivatePassword = ""
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

        PhysicalDisplays {
            width: parent.width
            outputs: popout.backend.physicalOutputs
            primaryOutput: popout.backend.primaryOutput
            busy: popout.backend.busy
            friendlyName: popout.backend.friendlyName
            hz: popout.backend.hz
            onToggleRequested: output => popout.backend.toggleOutput(output)
        }

        DisplayModes {
            width: parent.width
            sectionVisible: popout.backend.canConfigureSecondary
            expanded: popout.backend.modesExpanded
            currentMode: popout.backend.currentMode
            mirrorActive: popout.backend.mirrorActive
            wlMirrorInstalled: popout.backend.wlMirrorInstalled
            busy: popout.backend.busy
            networkBusy: popout.backend.networkBusy
            virtualTransitioning: popout.backend.virtualTransitioning

            onExpansionRequested: expanded => {
                popout.backend.modesExpanded = expanded
                if (expanded) {
                    popout.backend.resolutionExpanded = false
                    popout.backend.audioExpanded = false
                    popout.backend.networkExpanded = false
                    popout.backend.closePrivateLan()
                }
            }
            onActionRequested: action => {
                if (action === "primary")
                    popout.backend.onlyPrimary()
                else if (action === "duplicate")
                    popout.backend.duplicatePrimary()
                else if (action === "extend")
                    popout.backend.extendAll()
            }
        }

        VirtualMonitor {
            width: parent.width
            virtualReady: popout.backend.virtualReady
            virtualEnabled: popout.backend.virtualEnabled
            controlsVisible: popout.backend.virtualControlsVisible
            interactive: popout.backend.virtualInteractive
            networkBusy: popout.backend.networkBusy
            virtualTransitioning: popout.backend.virtualTransitioning
            detailText: popout.backend.virtualDetail()
            virtualWidth: popout.backend.virtualWidth
            virtualHeight: popout.backend.virtualHeight
            virtualRefresh: popout.backend.virtualRefresh
            virtualModes: popout.backend.virtualModes
            audioMode: popout.backend.virtualAudioMode
            resolutionExpanded: popout.backend.resolutionExpanded
            audioExpanded: popout.backend.audioExpanded
            busy: popout.backend.busy

            onToggleRequested: popout.backend.toggleVirtual()
            onResolutionExpansionRequested: expanded => {
                popout.backend.resolutionExpanded = expanded
                if (expanded) {
                    popout.backend.modesExpanded = false
                    popout.backend.audioExpanded = false
                    popout.backend.networkExpanded = false
                    popout.backend.closePrivateLan()
                }
            }
            onModeRequested: mode => popout.backend.setVirtualMode(mode)
            onAudioExpansionRequested: expanded => {
                popout.backend.audioExpanded = expanded
                if (expanded) {
                    popout.backend.resolutionExpanded = false
                    popout.backend.modesExpanded = false
                    popout.backend.networkExpanded = false
                    popout.backend.closePrivateLan()
                }
            }
            onAudioRequested: mode => popout.backend.setVirtualAudio(mode)
        }

        NetworkMode {
            width: parent.width
            sectionVisible: popout.backend.virtualPresent
            expanded: popout.backend.networkExpanded
            networkReady: popout.backend.networkReady
            networkEnabled: popout.backend.networkEnabled
            privateLanActive: popout.backend.privateLanActive
            busy: popout.backend.busy
            networkBusy: popout.backend.networkBusy
            networkMode: popout.backend.networkMode
            modeLabel: popout.backend.networkModeLabel(popout.backend.networkMode)
            detailText: popout.backend.networkDetail()

            onExpansionRequested: expanded => {
                popout.backend.networkExpanded = expanded
                if (expanded) {
                    popout.backend.modesExpanded = false
                    popout.backend.resolutionExpanded = false
                    popout.backend.audioExpanded = false
                    popout.backend.closePrivateLan()
                }
            }
            onModeRequested: mode => popout.backend.setNetworkMode(mode)
        }

        PrivateLan {
            width: parent.width
            sectionVisible: popout.backend.virtualPresent && popout.backend.privateLanActive
            expanded: popout.backend.privateLanExpanded
            detailText: popout.backend.privateLanDetail()
            hostVisible: popout.backend.networkHostVisible
            passwordVisible: popout.backend.networkPasswordVisible
            hostValue: popout.backend.networkHostAddress
            passwordValue: popout.backend.networkPrivatePassword
            copiedField: popout.copiedField
            hiddenValue: popout.backend.hiddenValue

            onExpansionRequested: expanded => {
                popout.backend.privateLanExpanded = expanded
                popout.backend.networkExpanded = false
                if (!expanded)
                    popout.backend.closePrivateLan()
            }
            onSecretRequested: (field, button) => {
                const generation = popout.backend.networkSecretGeneration
                popout.backend.fetchNetworkSecret(field, (ok, freshValue) => {
                    if (!ok || generation !== popout.backend.networkSecretGeneration
                            || !popout.backend.privateLanActive || !popout.backend.privateLanExpanded)
                        return
                    if (button === Qt.RightButton) {
                        popout.copyValue(freshValue, field)
                        return
                    }
                    if (field === "host") {
                        popout.backend.networkHostAddress = freshValue
                        popout.backend.networkHostVisible = !popout.backend.networkHostVisible
                    } else {
                        popout.backend.networkPrivatePassword = freshValue
                        popout.backend.networkPasswordVisible = !popout.backend.networkPasswordVisible
                        if (!popout.backend.networkPasswordVisible)
                            popout.backend.networkPrivatePassword = ""
                    }
                })
            }
        }

        StyledText {
            visible: popout.backend.lastError.length > 0
            width: parent.width
            text: popout.backend.lastError
            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }
    }
}
