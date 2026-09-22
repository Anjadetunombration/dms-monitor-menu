import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: section

    required property var outputs
    required property string primaryOutput
    required property bool busy
    required property var friendlyName
    required property var hz

    signal toggleRequested(var output)

    spacing: Theme.spacingS

    Repeater {
        model: section.outputs

        delegate: StyledRect {
            property var outputData: modelData

            width: parent.width
            height: 58
            radius: Theme.cornerRadius
            color: outputMouse.containsMouse && outputData.name !== section.primaryOutput
                   ? Theme.surfaceContainerHighest
                   : Theme.surfaceContainerHigh

            DankIcon {
                id: displayIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                name: outputData.name === section.primaryOutput ? "laptop" : "monitor"
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
                    text: section.friendlyName(outputData.name)
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: outputData.name
                          + (outputData.width > 0
                             ? " · " + outputData.width + "×" + outputData.height
                               + " · " + section.hz(outputData.refresh) + " Hz"
                             : "")
                          + (outputData.name === section.primaryOutput ? " · Principal" : "")
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
                enabled: outputData.name !== section.primaryOutput && !section.busy
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: section.toggleRequested(outputData)
            }
        }
    }
}
