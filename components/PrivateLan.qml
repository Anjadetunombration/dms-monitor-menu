import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: section

    required property bool sectionVisible
    required property bool expanded
    required property string detailText
    required property bool hostVisible
    required property bool passwordVisible
    required property string hostValue
    required property string passwordValue
    required property string copiedField
    required property var hiddenValue

    signal expansionRequested(bool expanded)
    signal secretRequested(string field, int button)

    visible: sectionVisible
    spacing: Theme.spacingS

    StyledRect {
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
                text: section.detailText
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
                name: section.expanded ? "expand_less" : "chevron_right"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: privateLanMouse
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
                { field: "host", label: "Host", icon: "lan" },
                { field: "password", label: "Clave", icon: "key" }
            ]

            delegate: StyledRect {
                property var secretData: modelData
                readonly property bool revealed: secretData.field === "host"
                    ? section.hostVisible : section.passwordVisible
                readonly property string value: secretData.field === "host"
                    ? section.hostValue : section.passwordValue

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
                        text: section.copiedField === secretData.field
                            ? (secretData.field === "host" ? "Copiado" : "Copiada")
                            : section.hiddenValue(value, revealed)
                        color: (revealed || section.copiedField === secretData.field)
                            ? Theme.primary : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    DankIcon {
                        name: section.copiedField === secretData.field
                            ? "check" : (revealed ? "visibility_off" : "visibility")
                        size: Theme.iconSizeSmall
                        color: section.copiedField === secretData.field
                            ? Theme.primary : Theme.surfaceVariantText
                    }
                }

                MouseArea {
                    id: secretMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => section.secretRequested(secretData.field, mouse.button)
                }
            }
        }
    }
}
