import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: section

    required property bool sectionVisible
    required property bool expanded
    required property string currentMode
    required property bool mirrorActive
    required property bool wlMirrorInstalled
    required property bool busy
    required property bool networkBusy
    required property bool virtualTransitioning

    signal expansionRequested(bool expanded)
    signal actionRequested(string action)

    visible: sectionVisible
    spacing: Theme.spacingS

    StyledRect {
        width: parent.width
        height: 48
        radius: Theme.cornerRadius
        color: modeMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

        DankIcon {
            id: modeIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: section.mirrorActive ? "content_copy" : "view_carousel"
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
                text: section.currentMode
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
            id: modeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: section.expansionRequested(!section.expanded)
        }
    }

    Column {
        visible: section.expanded
        width: parent.width
        spacing: Theme.spacingXS

        Repeater {
            model: [
                { label: "Solo principal", icon: "laptop", action: "primary", enabled: true },
                { label: "Duplicar", icon: "content_copy", action: "duplicate", enabled: section.wlMirrorInstalled },
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
                    visible: modeData.action === "duplicate" && !section.wlMirrorInstalled
                    text: "requiere wl-mirror"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                MouseArea {
                    id: modeOptionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: modeData.enabled && !section.busy && !section.networkBusy
                        && !section.virtualTransitioning
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: section.actionRequested(modeData.action)
                }
            }
        }
    }
}
