import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: section

    required property bool virtualReady
    required property bool virtualEnabled
    required property bool controlsVisible
    required property bool interactive
    required property bool networkBusy
    required property bool virtualTransitioning
    required property string detailText
    required property int virtualWidth
    required property int virtualHeight
    required property int virtualRefresh
    required property var virtualModes
    required property string audioMode
    required property bool resolutionExpanded
    required property bool audioExpanded
    required property bool busy

    signal toggleRequested()
    signal resolutionExpansionRequested(bool expanded)
    signal modeRequested(string mode)
    signal audioExpansionRequested(bool expanded)
    signal audioRequested(string mode)

    spacing: Theme.spacingS

    StyledRect {
        width: parent.width
        height: 58
        radius: Theme.cornerRadius
        color: virtualMouse.containsMouse && section.virtualReady
               ? Theme.surfaceContainerHighest
               : Theme.surfaceContainerHigh
        opacity: section.virtualReady ? 1.0 : 0.65

        DankIcon {
            id: virtualIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: "cast"
            size: Theme.iconSize
            color: section.virtualEnabled ? Theme.primary : Theme.surfaceText
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
                text: section.detailText
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
            text: section.virtualEnabled ? "ON" : "OFF"
            color: section.virtualEnabled ? Theme.primary : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            id: virtualMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: section.virtualReady && !section.busy && !section.networkBusy
                && !section.virtualTransitioning
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: section.toggleRequested()
        }
    }

    StyledRect {
        visible: section.controlsVisible
        width: parent.width
        height: 48
        radius: Theme.cornerRadius
        color: resolutionMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        opacity: section.interactive ? 1.0 : 0.55

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
                text: section.virtualWidth + "×" + section.virtualHeight
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            DankIcon {
                name: section.resolutionExpanded ? "expand_less" : "chevron_right"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: resolutionMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: section.interactive && section.virtualModes.length > 0
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: section.resolutionExpansionRequested(!section.resolutionExpanded)
        }
    }

    Column {
        visible: section.interactive && section.resolutionExpanded
        width: parent.width
        spacing: Theme.spacingXS

        Repeater {
            model: section.virtualModes

            delegate: StyledRect {
                property var resolutionData: modelData
                readonly property bool selected: section.virtualWidth === resolutionData.width
                                                 && section.virtualHeight === resolutionData.height
                                                 && Math.abs(section.virtualRefresh - resolutionData.refresh) < 1000

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
                    enabled: !section.busy && !selected
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: section.modeRequested(resolutionData.mode)
                }
            }
        }
    }

    StyledRect {
        visible: section.controlsVisible
        width: parent.width
        height: 48
        radius: Theme.cornerRadius
        color: audioMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        opacity: section.interactive ? 1.0 : 0.55

        DankIcon {
            id: audioIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            name: section.audioMode === "virtual" ? "cast_connected" : "volume_up"
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
                text: section.audioMode === "virtual" ? "Virtual" : "Local"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            DankIcon {
                name: section.audioExpanded ? "expand_less" : "chevron_right"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: audioMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: section.interactive
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: section.audioExpansionRequested(!section.audioExpanded)
        }
    }

    Column {
        visible: section.interactive && section.audioExpanded
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
                readonly property bool selected: section.audioMode === audioData.mode

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
                    enabled: !section.busy && !selected
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: section.audioRequested(audioData.mode)
                }
            }
        }
    }
}
