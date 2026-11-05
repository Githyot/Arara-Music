import QtQuick
import AraraStyle

// Adwaita "flat" button: transparent until hovered; `suggested` gives the blue pill.
Rectangle {
    id: root
    property string icon: ""
    property string text: ""
    property bool suggested: false
    property bool circular: false
    property bool checked: false
    property int size: 34
    signal clicked()

    implicitWidth: text !== "" ? label.implicitWidth + 24 : size
    implicitHeight: size
    radius: circular ? height / 2 : Theme.radius
    color: suggested ? (ma.pressed ? Qt.darker(Theme.accent, 1.15) : ma.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
         : checked ? Theme.selected
         : ma.pressed ? Theme.pressed : ma.containsMouse ? Theme.hover : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text !== "" ? root.text : Theme.glyph(root.icon)
        color: root.suggested ? "white" : Theme.fg
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
