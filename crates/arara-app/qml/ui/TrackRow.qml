import QtQuick
import AraraStyle

// AdwActionRow-like track row inside a "boxed-list" card.
// Hover shows the favourite star and the "⋮" menu button.
Rectangle {
    id: row
    property var track
    property int number: 0
    property bool showArt: false
    // Over the player panel's cover-coloured backdrop: white text.
    property bool onDark: false
    // Narrow rows (queue panel): the ⋮/trash button takes the duration's place on hover.
    readonly property bool compact: width < 380
    readonly property bool showBtn: !compact || ma.containsMouse || moreBtn.hovered
    readonly property color fgC: onDark ? "white" : Theme.fg
    readonly property color dimC: onDark ? Qt.rgba(1, 1, 1, 0.62) : Theme.dimFg
    readonly property color hiC: onDark ? "white" : Theme.accentFg
    property bool playing: false
    // On an album page the album artist is already in the header: hide it per row.
    property string hideArtist: ""
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
    color: ma.containsMouse || starBtn.hovered || moreBtn.hovered ? (onDark ? Qt.rgba(1, 1, 1, 0.1) : Theme.hover) : "transparent"

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
        Icon { anchors.centerIn: parent; name: "drag"; size: 16; color: row.dimC; opacity: hm.containsMouse || hm.pressed ? 1 : 0.6 }
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
            Icon { visible: !row.showArt && row.playing; anchors.centerIn: parent; name: "play"; size: 12; color: row.hiC }
            Text {
                visible: !row.showArt && !row.playing
                anchors.centerIn: parent
                text: row.number + 1
                color: row.playing ? row.hiC : row.dimC
                font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
            CoverArt {
                visible: row.showArt
                anchors.fill: parent; radius: 4
                source: row.track ? row.track.cover : ""
                decode: 76
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(60, row.width - handle.width - (row.showArt ? 38 : 22) - 26 - rightRow.width - 24)
            Row {
                width: parent.width
                spacing: 6
                Text {
                    id: titleText
                    width: Math.min(implicitWidth, parent.width - (eBadge.visible ? eBadge.width + parent.spacing : 0))
                    text: row.track ? row.track.title : ""
                    color: row.playing ? row.hiC : row.fgC
                    elide: Text.ElideRight
                    font.family: Theme.font; font.pointSize: Theme.fontSize
                }
                ExplicitBadge {
                    id: eBadge
                    anchors.verticalCenter: titleText.verticalCenter
                    track: row.track
                    size: 14
                    fill: row.dimC
                    ink: row.onDark ? "#3a3a3a" : Theme.cardBg
                }
            }
            Text {
                width: parent.width
                // Files without tags have no artist/album: show just the title, centered.
                text: !row.track ? "" : [row.track.artist === row.hideArtist ? "" : row.track.artist, row.showArt ? row.track.album : ""].filter(function (x) { return !!x }).join(" — ")
                visible: text !== ""
                color: row.dimC; elide: Text.ElideRight
                font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
        }
    }

    Row {
        id: rightRow
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 2
        Icon {
            visible: !!(row.track && row.track.remote) && row.width >= 380
            anchors.verticalCenter: parent.verticalCenter
            name: "cloud"; size: 14; color: row.dimC; opacity: 0.8
        }
        Item { visible: !!(row.track && row.track.remote) && row.width >= 380; width: 4; height: 1 }
        // Quality badge (Hi-Res / Sem perdas), from the file's format
        Rectangle {
            visible: !!(row.track && row.track.quality) && row.width > 520
            anchors.verticalCenter: parent.verticalCenter
            width: qText.implicitWidth + 10; height: 18; radius: 9
            color: "transparent"; border.color: row.dimC; border.width: 1; opacity: 0.8
            Text { id: qText; anchors.centerIn: parent; text: row.track && row.track.quality ? row.track.quality : ""; color: row.dimC; font.family: Theme.font; font.pointSize: Theme.fontSize - 3; font.weight: Font.Bold }
        }
        Item { visible: !!(row.track && row.track.quality) && row.width > 520; width: 6; height: 1 }
        FlatButton {
            id: starBtn
            iconColor: row.onDark ? "white" : undefined
            size: 30; circular: true
            icon: row.starred ? "star" : "unstar"
            // In narrow rows (the queue panel) only starred tracks keep the star.
            visible: row.starred || row.width >= 380
            opacity: row.starred || ma.containsMouse || hovered ? 1 : 0
            onClicked: { row.starred = !row.starred; row.starToggled(row.track, row.starred) }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.compact || !row.showBtn
            width: row.compact ? 34 : 44; horizontalAlignment: Text.AlignRight
            text: row.track ? fmt(row.track.duration) : ""
            color: row.dimC
            font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            function fmt(ms) { var s = Math.round(ms / 1000); return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2) }
        }
        FlatButton {
            id: moreBtn
            visible: row.showBtn
            iconColor: row.onDark ? "white" : undefined
            size: 30; circular: true
            icon: row.removable ? "trash" : "more"
            onClicked: {
                if (row.removable) { row.removeRequested(); return }
                var p = moreBtn.mapToItem(null, 0, moreBtn.height); row.menuRequested(row.track, p.x, p.y)
            }
        }
    }
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: row.onDark ? Qt.rgba(1, 1, 1, 0.1) : Theme.border; opacity: 0.5 }
}
