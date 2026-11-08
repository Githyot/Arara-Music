import QtQuick
import AraraStyle
import QtQuick.Controls.Basic as QQC

// Generic list page (Favoritas, Recentes, Mais tocadas, a playlist):
// header with title and actions, then a boxed, virtualized track list.
Item {
    id: page
    property string title: ""
    property string subtitle: ""
    property string emptyText: "Nada aqui ainda"
    property string emptyHint: ""
    property string emptyIcon: "songs"
    property var tracks: []
    property int playingId: -1
    property bool removable: false
    property bool editable: false
    signal play(var tracks, int index)
    signal menuRequested(var track, real x, real y)
    signal starToggled(var track, bool starred)
    signal removeAt(int index)
    signal moveItem(int from, int to)
    DragReorder { id: reorder; view: lv; onMoved: (f, t) => page.moveItem(f, t) }
    signal renameRequested()
    signal deleteRequested()

    readonly property int side: Math.max(24, (width - 900) / 2)

    ListView {
        QQC.ScrollBar.vertical: OverlayScrollBar {}
        id: lv
        anchors.fill: parent
        clip: true
        model: page.tracks
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: 24

        header: Item {
            width: lv.width
            height: head.height + 36
            Column {
                id: head
                x: page.side; y: 24
                width: lv.width - 2 * page.side
                spacing: 6
                Text { text: page.title; color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize; font.weight: Theme.titleWeight; width: parent.width; elide: Text.ElideRight }
                Text { visible: text !== "" && page.tracks.length > 0; text: page.subtitle; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                Item { width: 1; height: 6 }
                Row {
                    spacing: 8
                    visible: page.tracks.length > 0 || page.editable
                    FlatButton { visible: page.tracks.length > 0; text: "Reproduzir"; suggested: true; onClicked: page.play(page.tracks, 0) }
                    FlatButton {
                        visible: page.tracks.length > 1; text: "Aleatório"; color: Theme.hover
                        onClicked: {
                            var t = page.tracks.slice()
                            for (var i = t.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var x = t[i]; t[i] = t[j]; t[j] = x }
                            page.play(t, 0)
                        }
                    }
                    FlatButton { visible: page.editable; text: "Renomear"; color: Theme.hover; onClicked: page.renameRequested() }
                    FlatButton { visible: page.editable; text: "Excluir"; color: Theme.hover; onClicked: page.deleteRequested() }
                }
            }
        }

        delegate: Item {
            required property var modelData
            required property int index
            width: lv.width; height: 54
            Rectangle {
                anchors { fill: parent; leftMargin: page.side; rightMargin: page.side }
                color: Theme.cardBg
                radius: Theme.cardRadius
                // square off the inner corners so consecutive rows read as one card
                Rectangle { visible: index > 0; anchors { left: parent.left; right: parent.right; top: parent.top } height: Theme.cardRadius; color: parent.color }
                Rectangle { visible: index < page.tracks.length - 1; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: Theme.cardRadius; color: parent.color }
                clip: true
                TrackRow {
                    anchors.fill: parent
                    track: modelData; number: index; showArt: true
                    playing: modelData.id === page.playingId
                    removable: page.removable
                    draggable: page.removable
                    dropMark: reorder.mark(index)
                    onDragStart: reorder.start(index)
                    onDragMove: (y) => reorder.move(y)
                    onDragEnd: reorder.end()
                    onActivated: page.play(page.tracks, index)
                    onMenuRequested: (t, x, y) => page.menuRequested(t, x, y)
                    onStarToggled: (t, s) => page.starToggled(t, s)
                    onRemoveRequested: page.removeAt(index)
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: page.tracks.length === 0
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: page.emptyIcon; size: 96; color: Theme.dimFg; opacity: 0.6 }
        Item { width: 1; height: 8 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: page.emptyText; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize + 1; font.weight: Theme.headingWeight }
        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: text !== ""; text: page.emptyHint; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize }
    }
}
