import QtQuick
import AraraStyle

// AdwActionRow-like track row inside a "boxed-list" card.
// Hover shows the favourite star and the "⋮" menu button.
Rectangle {
    id: row
    property var track
    property int number: 0
    property bool showArt: false
    property bool playing: false
    property bool removable: false
    property bool draggable: false
    // Drop indicator: -1 none, 0 line above, 1 line below
    property int dropMark: -1
    signal dragStart()
    signal dragMove(real sceneY)
    signal dragEnd()
    property bool starred: track ? !!track.starred : false
    signal activated()
    signal starToggled(var track, bool starred)
    signal menuRequested(var track, real x, real y)
    signal removeRequested()

    height: 54
    color: ma.containsMouse || starBtn.hovered || moreBtn.hovered ? Theme.hover : "transparent"

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
            if (m.button === Qt.RightButton) {
                var p = row.mapToItem(null, m.x, m.y); row.menuRequested(row.track, p.x, p.y)
            } else row.activated()
        }
    }

    Item {
        id: handle
        visible: row.draggable
        width: visible ? 28 : 0; height: parent.height
        anchors { left: parent.left; leftMargin: 4 }
        Icon { anchors.centerIn: parent; name: "drag"; size: 16; color: Theme.dimFg; opacity: hm.containsMouse || hm.pressed ? 1 : 0.6 }
        MouseArea {
            id: hm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true
            onPressed: row.dragStart()
            onPositionChanged: (m) => { if (pressed) row.dragMove(mapToItem(null, m.x, m.y).y) }
            onReleased: row.dragEnd()
            onCanceled: row.dragEnd()
        }
    }
    Rectangle { visible: row.dropMark === 0; anchors { left: parent.left; right: parent.right; top: parent.top } height: 2; color: Theme.accent; z: 5 }
    Rectangle { visible: row.dropMark === 1; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 2; color: Theme.accent; z: 5 }

    Row {
        anchors { left: handle.right; leftMargin: row.draggable ? 2 : 14; verticalCenter: parent.verticalCenter }
        spacing: 12
        Item {
            width: row.showArt ? 38 : 22; height: 38
            Icon { visible: !row.showArt && row.playing; anchors.centerIn: parent; name: "play"; size: 12; color: Theme.accentFg }
            Text {
                visible: !row.showArt && !row.playing
                anchors.centerIn: parent
                text: row.number + 1
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
            width: row.width - 230
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

    Row {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 2
        Icon {
            visible: !!(row.track && row.track.remote)
            anchors.verticalCenter: parent.verticalCenter
            name: "cloud"; size: 14; color: Theme.dimFg; opacity: 0.8
        }
        Item { visible: !!(row.track && row.track.remote); width: 4; height: 1 }
        FlatButton {
            id: starBtn
            size: 30; circular: true
            icon: row.starred ? "star" : "unstar"
            opacity: row.starred || ma.containsMouse || hovered ? 1 : 0
            onClicked: { row.starred = !row.starred; row.starToggled(row.track, row.starred) }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 44; horizontalAlignment: Text.AlignRight
            text: row.track ? fmt(row.track.duration) : ""
            color: Theme.dimFg
            font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            function fmt(ms) { var s = Math.round(ms / 1000); return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2) }
        }
        FlatButton {
            id: moreBtn
            size: 30; circular: true
            icon: row.removable ? "trash" : "more"
            onClicked: {
                if (row.removable) { row.removeRequested(); return }
                var p = moreBtn.mapToItem(null, 0, moreBtn.height); row.menuRequested(row.track, p.x, p.y)
            }
        }
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border; opacity: 0.5 }
}
