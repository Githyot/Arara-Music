import QtQuick
import AraraStyle

// Navigation row. One component, four selection languages:
//   GNOME    grey rounded highlight
//   Apple    grey highlight, icons always in the accent colour
//   Material pill in the accent's tonal colour, bold label
//   Fluent   subtle fill plus a short accent bar on the left
Rectangle {
    id: row
    property string icon: ""
    property string text: ""
    property bool current: false
    property string badge: ""
    signal clicked()

    height: Theme.rowHeight
    radius: Theme.material ? height / 2 : Theme.radius
    color: current ? Theme.selected : ma.pressed ? Theme.pressed : ma.containsMouse ? Theme.hover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.ms(90) } }

    Rectangle {
        visible: Theme.fluent && row.current
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 3; height: Math.round(row.height * 0.45); radius: 1.5
        color: Theme.accent
    }
    Row {
        anchors { left: parent.left; leftMargin: Theme.material ? 16 : Theme.apple ? 8 : 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: Theme.material ? 12 : Theme.apple ? 8 : 12
        Icon {
            id: ic; anchors.verticalCenter: parent.verticalCenter; name: row.icon; size: 16
            color: Theme.apple ? Theme.accent : (Theme.material && row.current) ? Theme.fg : Theme.fg
            opacity: Theme.material && !row.current ? 0.8 : 1
        }
        Text {
            width: parent.width - ic.width - parent.spacing - (bd.visible ? bd.width + 6 : 0)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight; text: row.text; color: Theme.fg
            font.family: Theme.font; font.pointSize: Theme.fontSize
            font.weight: Theme.material && row.current ? Font.DemiBold : Font.Normal
        }
    }
    Text {
        id: bd
        visible: row.badge !== ""
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: row.badge; color: Theme.dimFg
        font.family: Theme.font; font.pointSize: Theme.fontSize - 1
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: row.clicked() }
}
