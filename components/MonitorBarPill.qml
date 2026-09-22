import QtQuick
import qs.Common
import qs.Widgets

StyledRect {
    id: pill

    required property bool vertical
    required property real widgetThickness
    required property int widgetIconSize
    required property bool active
    required property bool forcePadding
    required property int barPadding

    readonly property real innerPadding: forcePadding ? barPadding : 0

    implicitWidth: vertical ? 0 : Math.max(widgetThickness, widgetIconSize + innerPadding * 2)
    width: vertical ? widgetThickness : implicitWidth
    implicitHeight: vertical ? Math.max(widgetThickness, widgetIconSize + innerPadding * 2) : 0
    height: vertical ? implicitHeight : widgetThickness
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh

    DankIcon {
        anchors.centerIn: parent
        name: "desktop_windows"
        size: pill.widgetIconSize
        color: pill.active ? Theme.primary : Theme.surfaceText
    }
}
