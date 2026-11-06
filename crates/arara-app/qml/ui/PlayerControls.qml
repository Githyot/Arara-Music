import QtQuick
import QtQuick.Controls.Basic
import AraraStyle

// Seek bar with elapsed / remaining time, transport buttons and a wide
// volume bar. Used by the right-hand player panel and the lyrics screen.
Column {
    id: pc
    property bool playing: false
    property real position: 0
    property real duration: 0
    property bool shuffle: false
    property string repeat: "off"
    property real volume: 1.0
    property bool onDark: false
    signal toggle()
    signal next()
    signal prev()
    signal seek(real ms)
    signal toggleShuffle()
    signal cycleRepeat()
    signal volumeMoved(real v)

    readonly property color ink: onDark ? "white" : Theme.fg
    readonly property color dim: onDark ? Qt.rgba(1, 1, 1, 0.7) : Theme.dimFg
    function fmt(ms) { var s = Math.max(0, Math.floor(ms / 1000)); return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2) }
    spacing: 10

    Item {
        width: parent.width; height: 40
        ThemedSlider {
            id: seekBar
            anchors { left: parent.left; right: parent.right; top: parent.top }
            onDark: pc.onDark
            from: 0; to: Math.max(1, pc.duration)
            // Depends on the duration too: a position restored before the file
            // is loaded was clamped to the old range and the bar stayed empty.
            value: pressed ? value : Math.min(pc.position, Math.max(1, pc.duration))
            onMoved: pc.seek(value)
        }
        Text {
            anchors { left: parent.left; bottom: parent.bottom }
            text: pc.fmt(seekBar.pressed ? seekBar.value : pc.position)
            color: pc.dim; font.family: Theme.font; font.pointSize: Theme.fontSize - 2
        }
        Text {
            anchors { right: parent.right; bottom: parent.bottom }
            text: pc.duration <= 0 ? "0:00" : Prefs.remainingTime ? "-" + pc.fmt(pc.duration - (seekBar.pressed ? seekBar.value : pc.position)) : pc.fmt(pc.duration)
            color: pc.dim; font.family: Theme.font; font.pointSize: Theme.fontSize - 2
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        FlatButton { anchors.verticalCenter: parent.verticalCenter; icon: "shuffle"; circular: true; checked: pc.shuffle; iconColor: pc.onDark && !pc.shuffle ? "white" : undefined; onClicked: pc.toggleShuffle() }
        FlatButton { anchors.verticalCenter: parent.verticalCenter; icon: "prev"; circular: true; size: 40; iconColor: pc.onDark ? "white" : undefined; onClicked: pc.prev() }
        // GNOME/Fluent: accent circle. Material: rounded-square FAB. Apple: a big bare glyph.
        FlatButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: pc.playing ? "pause" : "play"
            circular: !Theme.material
            corner: Theme.material ? 18 : -1
            suggested: !Theme.apple
            size: Theme.material ? 60 : Theme.fluent ? 48 : 52
            iconSize: Theme.apple ? 30 : 20
            iconColor: Theme.apple ? pc.ink : undefined
            onClicked: pc.toggle()
        }
        FlatButton { anchors.verticalCenter: parent.verticalCenter; icon: "next"; circular: true; size: 40; iconColor: pc.onDark ? "white" : undefined; onClicked: pc.next() }
        FlatButton { anchors.verticalCenter: parent.verticalCenter; icon: pc.repeat === "one" ? "repeat1" : "repeat"; circular: true; checked: pc.repeat !== "off"; iconColor: pc.onDark && pc.repeat === "off" ? "white" : undefined; onClicked: pc.cycleRepeat() }
    }

    VolumeSlider {
        width: parent.width
        volume: pc.volume
        onDark: pc.onDark
        onMoved: (v) => pc.volumeMoved(v)
    }
}
