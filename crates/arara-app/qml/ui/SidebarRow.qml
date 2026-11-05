import QtQuick
import AraraStyle

// Row of an AdwNavigationSplitView sidebar ("navigation-sidebar" style).
Rectangle {
    id: row
    property string icon: ""
    property string text: ""
    property bool current: false
    signal clicked()

    height: 38
    radius: Theme.radius
    color: current ? Theme.selected : ma.containsMouse ? Theme.hover : "transparent"

    Row {
        anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 12
        Icon { id: ic; anchors.verticalCenter: parent.verticalCenter; name: row.icon; size: 16 }
        Text { width: parent.width - ic.width - 12; elide: Text.ElideRight; text: row.text; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: row.clicked() }
}
