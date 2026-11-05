import QtQuick
import AraraStyle
import io.github.arara

// All songs / search results, backed by the Rust TrackModel: rows live in
// Rust and only the visible delegates exist, so 50k+ tracks scroll smoothly.
Item {
    id: page
    property string query: ""
    property int playingId: -1
    property bool loaded: false
    signal play(var tracks, int index)
    signal menuRequested(var track, real x, real y)
    signal starToggled(var track, bool starred)

    function search(q) { query = q; model.search(q); loaded = true }
    function reload() { model.search(query); loaded = true }
    onVisibleChanged: if (visible && !loaded) reload()

    TrackModel { id: model }

    readonly property int side: Math.max(24, (width - 900) / 2)

    ListView {
        id: lv
        anchors.fill: parent
        clip: true
        model: model
        reuseItems: true
        cacheBuffer: 540
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: 18

        header: Item {
            width: lv.width; height: 48
            Text {
                x: page.side; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                text: (page.query === "" ? "Todas as músicas · " : "Resultados · ") + model.count.toLocaleString(Qt.locale(), "f", 0)
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
            }
        }

        delegate: Item {
            id: d
            required property int index
            required property var trackId
            required property string title
            required property string artist
            required property string album
            required property var albumId
            required property var duration
            required property bool starred
            required property string cover
            required property string coverBig
            required property string url
            required property bool remote
            readonly property var track: ({ id: Number(trackId), title: title, artist: artist, album: album,
                                            albumId: Number(albumId) >= 0 ? Number(albumId) : null, duration: Number(duration),
                                            starred: starred, cover: cover, coverBig: coverBig, url: url, remote: remote })
            width: lv.width; height: 54
            Rectangle {
                anchors { fill: parent; leftMargin: page.side; rightMargin: page.side }
                color: Theme.cardBg
                radius: Theme.cardRadius
                Rectangle { visible: d.index > 0; anchors { left: parent.left; right: parent.right; top: parent.top } height: Theme.cardRadius; color: parent.color }
                Rectangle { visible: d.index < model.count - 1; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: Theme.cardRadius; color: parent.color }
                TrackRow {
                    anchors.fill: parent
                    track: d.track; number: d.index; showArt: true
                    playing: d.track.id === page.playingId
                    // play from here on (bounded queue, so huge libraries don't build huge queues)
                    onActivated: page.play(JSON.parse(model.sliceJson(d.index, 500)), 0)
                    onMenuRequested: (t, x, y) => page.menuRequested(t, x, y)
                    onStarToggled: (t, s) => { model.setStarredAt(d.index, s); page.starToggled(t, s) }
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: page.loaded && model.count === 0
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "search"; size: 96; color: Theme.dimFg }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.query === "" ? "Nenhuma música na biblioteca" : "Nenhum resultado"
            color: Theme.fg; font.family: Theme.font; font.pointSize: 16; font.weight: Font.Bold
        }
    }
}
