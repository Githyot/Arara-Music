import QtQuick
import QtQuick.Controls.Basic

// Slider in the current look. `onDark` paints it white for the cover-coloured panels.
//   GNOME   5 px track, round knob on hover
//   Apple   thin track that thickens on hover, no knob
//   Material thick track, vertical bar handle
//   Fluent  4 px track, white knob with an accent dot (always shown)
Slider {
    id: s
    property bool onDark: false
    property color fill: onDark ? "white" : Theme.accent
    readonly property bool active: hovered || pressed
    property real trackH: Theme.apple ? (active ? 7 : 4) : Theme.material ? 8 : Theme.fluent ? 4 : 5
    implicitHeight: Theme.material ? 24 : 18
    Behavior on trackH { NumberAnimation { duration: Theme.ms(120) } }

    background: Item {
        x: s.leftPadding; y: s.topPadding + s.availableHeight / 2 - s.trackH / 2
        width: s.availableWidth; height: s.trackH
        // Material splits the track around the handle.
        Rectangle {
            x: Theme.material ? s.visualPosition * parent.width + 6 : 0
            width: Theme.material ? Math.max(0, parent.width - x) : parent.width
            height: parent.height; radius: height / 2
            color: s.onDark ? Qt.rgba(1, 1, 1, 0.25) : Theme.material ? Theme.selected : Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
        }
        Rectangle {
            width: Theme.material ? Math.max(0, s.visualPosition * parent.width - 6) : s.visualPosition * parent.width
            height: parent.height; radius: height / 2
            color: s.fill
        }
    }
    handle: Item {
        x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
        y: s.topPadding + s.availableHeight / 2 - height / 2
        width: Theme.material ? 4 : Theme.fluent ? 18 : 14
        height: Theme.material ? 22 : width
        visible: Theme.material || Theme.fluent || (Theme.gnome && s.active)
        Rectangle {
            anchors.fill: parent; radius: Theme.material ? 2 : width / 2
            color: Theme.material ? s.fill : Theme.fluent ? (Theme.dark ? "#454545" : "white") : "white"
            border.width: Theme.material ? 0 : 1
            border.color: Theme.fluent ? Theme.border : Qt.rgba(0, 0, 0, 0.15)
        }
        Rectangle {
            visible: Theme.fluent
            anchors.centerIn: parent
            width: s.pressed ? 8 : s.hovered ? 12 : 10; height: width; radius: width / 2
            color: s.fill
            Behavior on width { NumberAnimation { duration: Theme.ms(100) } }
        }
    }
}
