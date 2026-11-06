import QtQuick
import QtQuick.Controls.Basic
import AraraStyle

// Wide volume bar (speaker icons at both ends) for fine control.
Item {
    id: vs
    property real volume: 1.0
    property bool onDark: false
    signal moved(real v)
    readonly property color ink: onDark ? "white" : Theme.fg
    implicitHeight: 28

    property real last: 1.0
    FlatButton {
        id: low
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        size: 28; circular: true
        icon: vs.volume <= 0.001 ? "mute" : "volume-low"
        iconColor: vs.ink
        onClicked: { if (vs.volume > 0.001) { vs.last = vs.volume; vs.moved(0) } else vs.moved(vs.last) }
    }
    ThemedSlider {
        id: s
        anchors { left: low.right; right: high.left; leftMargin: 4; rightMargin: 4; verticalCenter: parent.verticalCenter }
        onDark: vs.onDark
        fill: vs.onDark ? "white" : Theme.material || Theme.fluent ? Theme.accent : Theme.fg
        from: 0; to: 1; value: vs.volume
        onMoved: vs.moved(value)
        WheelHandler { onWheel: (e) => vs.moved(Math.max(0, Math.min(1, vs.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)))) }
    }
    Icon {
        id: high
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        name: "volume"; size: 16; color: vs.ink; opacity: 0.8
    }
}
