import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: section

    required property bool sectionVisible
    required property bool expanded
    required property bool networkReady
    required property bool networkEnabled
    required property bool privateLanActive
    required property bool busy
    required property bool networkBusy
    required property string networkMode
    required property string modeLabel
    required property string detailText

    signal expansionRequested(bool expanded)
    signal modeRequested(string mode)

    visible: sectionVisible
    spacing: Theme.spacingS

    StyledRect {
        width: parent.width
        height: 58
        radius: Theme.cornerRadius
        color: networkMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        opacity: section.networkBusy ? 0.65 : 1.0

        DankIcon {
            id: networkIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: section.privateLanActive ? "lan" : "wifi"
            size: Theme.iconSize
            color: section.networkEnabled ? Theme.primary : Theme.surfaceText
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
                text: section.detailText
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
                text: section.modeLabel
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            DankIcon {
                name: section.expanded ? "expand_less" : "chevron_right"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: networkMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !section.busy && !section.networkBusy
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: section.expansionRequested(!section.expanded)
        }
    }

    Column {
        visible: section.expanded
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
                readonly property bool selected: section.networkMode === networkData.mode

                width: parent.width
                height: 42
                radius: Theme.cornerRadius
                color: networkOptionMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                opacity: section.networkReady ? 1.0 : 0.65

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
                    enabled: section.networkReady && !section.busy && !section.networkBusy && !selected
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: section.modeRequested(networkData.mode)
                }
            }
        }
    }
}
