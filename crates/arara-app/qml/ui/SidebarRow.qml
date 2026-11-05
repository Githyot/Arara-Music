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
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 12
        Text { text: Theme.glyph(row.icon); color: Theme.fg; font.pointSize: Theme.fontSize; width: 16; horizontalAlignment: Text.AlignHCenter }
        Text { text: row.text; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: row.clicked() }
}
