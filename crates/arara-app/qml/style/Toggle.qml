import QtQuick

// On/off switch drawn in the current look:
// GNOME pill with a white knob, macOS small pill, Material 3 track with a
// growing thumb and outline, Fluent outlined pill with a small dot.
Item {
    id: sw
    property bool checked: false
    signal toggled()
    readonly property real w: Theme.pick(46, 38, 52, 40)
    readonly property real h: Theme.pick(26, 22, 32, 20)
    implicitWidth: w; implicitHeight: h
    readonly property real knob: Theme.material ? (checked ? 24 : 16) * (ma.pressed ? 1.1 : 1)
        : Theme.fluent ? (ma.containsMouse ? 14 : 12)
        : h - 6
    readonly property color trackOn: Theme.accent
    readonly property color trackOff: Theme.material ? (Theme.dark ? "#36343b" : "#e6e0e9")
        : Theme.fluent ? "transparent"
        : Theme.dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.16)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? sw.trackOn : sw.trackOff
        border.width: !sw.checked && (Theme.material || Theme.fluent) ? (Theme.material ? 2 : 1) : 0
        border.color: Theme.material ? (Theme.dark ? "#938f99" : "#79747e") : Theme.dimFg
        Behavior on color { ColorAnimation { duration: Theme.ms(140) } }
    }
    Rectangle {
        width: sw.knob; height: sw.knob; radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? sw.w - width - (sw.h - width) / 2 : (sw.h - width) / 2
        color: sw.checked ? (Theme.material && Theme.dark ? "#381e72" : Theme.fluent && Theme.dark ? "#000000" : "white")
             : Theme.material ? (Theme.dark ? "#938f99" : "#79747e")
             : Theme.fluent ? Theme.dimFg : "white"
        border.width: Theme.gnome || Theme.apple ? 0.5 : 0
        border.color: Qt.rgba(0, 0, 0, 0.15)
        Behavior on x { NumberAnimation { duration: Theme.ms(160); easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.ms(120) } }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
}
