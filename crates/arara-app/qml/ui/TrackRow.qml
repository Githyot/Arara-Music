import QtQuick
import AraraStyle

// AdwActionRow-like track row inside a "boxed-list" card.
Rectangle {
    id: row
    property var track
    property int number: 0
    property bool showArt: false
    property bool playing: false
    signal activated()

    height: 54
    color: ma.containsMouse ? Theme.hover : "transparent"

    Row {
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 12
        Item {
            width: row.showArt ? 38 : 22; height: 38
            Text {
                visible: !row.showArt
                anchors.centerIn: parent
                text: row.playing ? Theme.glyph("play") : row.number + 1
                color: row.playing ? Theme.accentFg : Theme.dimFg
                font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
            Rectangle {
                visible: row.showArt
                anchors.fill: parent; radius: 4; color: Theme.cardBg; clip: true
                Image { anchors.fill: parent; source: row.track ? row.track.cover : ""; sourceSize: Qt.size(38, 38); asynchronous: true; cache: false }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: row.width - 160
            Text {
                width: parent.width
                text: row.track ? row.track.title : ""
                color: row.playing ? Theme.accentFg : Theme.fg
                elide: Text.ElideRight
                font.family: Theme.font; font.pointSize: Theme.fontSize
            }
            Text {
                width: parent.width
                text: row.track ? row.track.artist + (row.showArt && row.track.album ? " — " + row.track.album : "") : ""
                color: Theme.dimFg; elide: Text.ElideRight
                font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
        }
    }
    Text {
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        text: row.track ? fmt(row.track.duration) : ""
        color: Theme.dimFg
        font.family: Theme.font; font.pointSize: Theme.fontSize - 1
        function fmt(ms) { var s = Math.round(ms / 1000); return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2) }
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border; opacity: 0.5 }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onDoubleClicked: row.activated(); onClicked: row.activated() }
}
