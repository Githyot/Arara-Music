import QtQuick
import AraraStyle

// Collapsible sidebar section title. Click (or the chevron) folds the rows
// below it; an optional + button sits on the right.
Item {
    id: sh
    property string text: ""
    property bool collapsed: false
    property bool addButton: false
    property int count: -1          // shown next to the title while collapsed
    signal toggled()
    signal add()
    height: Theme.material ? 44 : 36

    Rectangle {
        anchors { fill: parent; topMargin: 6 }
        radius: Theme.material ? height / 2 : Theme.radius
        color: hm.containsMouse ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.ms(90) } }
    }
    Row {
        anchors { left: parent.left; leftMargin: Theme.material ? 16 : Theme.apple ? 8 : 12; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sh.text
            color: Theme.sectionDim ? Theme.dimFg : Theme.fg
            font.family: Theme.font; font.pointSize: Theme.sectionSize; font.weight: Theme.sectionWeight
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: sh.collapsed && sh.count > 0
            text: sh.count
            color: Theme.dimFg
            font.family: Theme.font; font.pointSize: Theme.sectionSize - 1
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "pan-end"; size: 12; color: Theme.dimFg
            // GNOME/Apple show the chevron on hover, like their sidebars; the others always.
            opacity: hm.containsMouse || sh.collapsed || Theme.material || Theme.fluent ? 1 : 0
            rotation: sh.collapsed ? 0 : 90
            Behavior on rotation { NumberAnimation { duration: Theme.ms(160); easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Theme.ms(120) } }
        }
    }
    MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sh.toggled() }
    FlatButton {
        visible: sh.addButton
        anchors { right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }
        size: 28; icon: "add"
        onClicked: sh.add()
    }
}
