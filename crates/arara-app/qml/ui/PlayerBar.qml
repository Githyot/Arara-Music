import QtQuick
import AraraStyle
import QtQuick.Controls.Basic

// Bottom bar (like AdwBottomSheet's bottom bar): art, title, transport, seek.
Rectangle {
    id: bar
    property var track: null
    property bool playing: false
    property real position: 0
    property real duration: 0
    property bool shuffle: false
    property string repeat: "off"   // off | all | one
    property real volume: 1.0
    signal toggle()
    signal toggleShuffle()
    signal cycleRepeat()
    signal volumeMoved(real v)
    signal next()
    signal prev()
    signal seek(real ms)
    signal expand()

    height: 72
    color: Theme.headerBg
    Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.border; opacity: 0.6 }

    Slider {
        id: seekBar
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: -7 }
        from: 0; to: Math.max(1, bar.duration)
        value: pressed ? value : bar.position
        onMoved: bar.seek(value)
        height: 14
        background: Rectangle {
            y: seekBar.height / 2 - 1.5; width: seekBar.width; height: 3; color: Theme.hover
            Rectangle { width: seekBar.visualPosition * parent.width; height: parent.height; color: Theme.accent }
        }
        handle: Rectangle {
            x: seekBar.visualPosition * (seekBar.width - width); y: seekBar.height / 2 - height / 2
            width: 14; height: 14; radius: 7; color: "white"; border.color: Theme.border
            visible: seekBar.hovered || seekBar.pressed
        }
    }

    Row {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 12
        width: parent.width / 2 - 100
        Rectangle {
            width: 48; height: 48; radius: Theme.radius; color: Theme.cardBg; clip: true
            Image { anchors.fill: parent; source: bar.track ? bar.track.cover : ""; sourceSize: Qt.size(48, 48); asynchronous: true; cache: false }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 60
            Text { width: parent.width; elide: Text.ElideRight; text: bar.track ? bar.track.title : "Nada tocando"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
            Text { width: parent.width; elide: Text.ElideRight; text: bar.track ? bar.track.artist : ""; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
        }
        MouseArea { width: 1; height: 1 }
    }
    MouseArea { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: parent.width / 2 - 100; onClicked: bar.expand(); cursorShape: Qt.PointingHandCursor }

    Row {
        anchors.centerIn: parent
        spacing: 8
        FlatButton { icon: "shuffle"; circular: true; checked: bar.shuffle; visible: bar.width > 560; onClicked: bar.toggleShuffle() }
        FlatButton { icon: "prev"; circular: true; onClicked: bar.prev() }
        FlatButton { icon: bar.playing ? "pause" : "play"; circular: true; suggested: true; size: 40; onClicked: bar.toggle() }
        FlatButton { icon: "next"; circular: true; onClicked: bar.next() }
        FlatButton { icon: bar.repeat === "one" ? "repeat1" : "repeat"; circular: true; checked: bar.repeat !== "off"; visible: bar.width > 560; onClicked: bar.cycleRepeat() }
    }

    Row {
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: fmt(bar.position) + " / " + fmt(bar.duration)
            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            function fmt(ms) { var s = Math.floor(ms / 1000); return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2) }
        }
        FlatButton {
            visible: bar.width > 860
            icon: bar.volume <= 0.001 ? "mute" : "volume"; circular: true; size: 30
            property real last: 1.0
            onClicked: { if (bar.volume > 0.001) { last = bar.volume; bar.volumeMoved(0) } else bar.volumeMoved(last) }
        }
        Slider {
            id: vol
            visible: bar.width > 860
            anchors.verticalCenter: parent.verticalCenter
            width: 90; height: 20
            from: 0; to: 1; value: bar.volume
            onMoved: bar.volumeMoved(value)
            background: Rectangle {
                y: vol.height / 2 - 2; width: vol.width; height: 4; radius: 2; color: Theme.hover
                Rectangle { width: vol.visualPosition * parent.width; height: parent.height; radius: 2; color: Theme.fg; opacity: 0.7 }
            }
            handle: Rectangle {
                x: vol.visualPosition * (vol.width - width); y: vol.height / 2 - height / 2
                width: 14; height: 14; radius: 7; color: "white"; border.color: Theme.border
            }
        }
        FlatButton { icon: "lyrics"; onClicked: bar.expand() }
    }
}
