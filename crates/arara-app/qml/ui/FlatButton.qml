import QtQuick
import AraraStyle

// Adwaita "flat" button: transparent until hovered; `suggested` gives the blue pill.
Rectangle {
    id: root
    property string icon: ""
    property string text: ""
    property bool suggested: false
    property bool destructive: false
    property bool circular: false
    property bool checked: false
    property int size: 34
    readonly property bool hovered: ma.containsMouse
    signal clicked()

    implicitWidth: text !== "" ? label.implicitWidth + 24 : size
    implicitHeight: size
    radius: circular ? height / 2 : Theme.radius
    readonly property color fill: destructive ? Theme.destructive : Theme.accent
    color: (suggested || destructive) ? (ma.pressed ? Qt.darker(fill, 1.15) : ma.containsMouse ? Qt.lighter(fill, 1.08) : fill)
         : checked ? Theme.selected
         : ma.pressed ? Theme.pressed : ma.containsMouse ? Theme.hover : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }

    Icon {
        anchors.centerIn: parent
        visible: root.text === "" && root.icon !== ""
        name: root.icon
        size: root.size >= 40 ? 20 : 16
        color: root.suggested || root.destructive ? "white" : (root.checked ? Theme.accentFg : Theme.fg)
    }
    Text {
        id: label
        anchors.centerIn: parent
        visible: root.text !== ""
        text: root.text
        color: root.suggested || root.destructive ? "white" : Theme.fg
        font.family: Theme.font
        font.pointSize: root.text !== "" ? Theme.fontSize : Math.round(root.size * 0.36)
        font.weight: root.text !== "" ? Font.DemiBold : Font.Normal
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
