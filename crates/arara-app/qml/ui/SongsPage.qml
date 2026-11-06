import QtQuick
import AraraStyle
import io.github.arara

// All songs / search results / one category, backed by the Rust TrackModel:
// rows live in Rust and only the visible delegates exist, so 50k+ tracks
// scroll smoothly. Sort orders, search scopes, a drag-able scroll bar and an
// A–Z index make big libraries quick to get around.
Item {
    id: page
    property string query: ""
    // Fixed filter for category pages, e.g. genero:"Rap" or pasta:"/music/x/".
    property string baseFilter: ""
    property string heading: ""
    property string sort: "artist"
    property string scope: "all"
    property bool userSorted: false
    property int playingId: -1
    property bool loaded: false
    property var sections: []
    signal play(var tracks, int index)
    signal menuRequested(var track, real x, real y)
    signal starToggled(var track, bool starred)
    signal saveSmart(string query, string sort)
    readonly property string fullQuery: (baseFilter + " " + scoped()).trim()

    readonly property var sortOptions: [
        { k: "", t: "Relevância" }, { k: "artist", t: "Artista" }, { k: "title", t: "Título" },
        { k: "album", t: "Álbum" }, { k: "added", t: "Adicionadas recentemente" }, { k: "year", t: "Ano" },
        { k: "plays", t: "Mais tocadas" }, { k: "duration", t: "Duração" }
    ]
    readonly property var scopes: [
        { k: "all", t: "Tudo" }, { k: "titulo", t: "Título" }, { k: "artista", t: "Artista" },
        { k: "album", t: "Álbum" }, { k: "genero", t: "Gênero" }, { k: "ano", t: "Ano" }, { k: "compositor", t: "Compositor" }
    ]
    readonly property bool hasText: query.trim() !== ""
    readonly property string effectiveSort: hasText && !userSorted && scope === "all" ? "" : (sort === "" && !hasText ? "artist" : sort)

    function sortLabel(k) { var o = sortOptions.find(function (x) { return x.k === k }); return o ? o.t : "" }
    function scoped() {
        var q = query.trim()
        if (q === "" || scope === "all") return q
        if (scope === "ano") return "ano:" + q.replace(/\s+/g, "")
        return scope + ":\"" + q.replace(/"/g, "") + "\""
    }
    function run() {
        model.query((baseFilter + " " + scoped()).trim(), effectiveSort)
        sections = JSON.parse(model.sections())
        loaded = true
        lv.positionViewAtBeginning()
    }
    function search(q) { query = q; run() }
    function reload() { run() }
    function open(filter, title, s) { baseFilter = filter; heading = title; sort = s || "artist"; userSorted = !!s; scope = "all"; query = ""; run() }
    onVisibleChanged: if (visible && !loaded) reload()

    TrackModel { id: model }

    readonly property int side: Math.max(24, (width - 900) / 2)
    readonly property int rightSide: Math.max(side, fast.width + 16)

    // ---- toolbar ----
    Column {
        id: bar
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: page.side; rightMargin: page.rightSide; topMargin: 14 }
        spacing: 8
        Item {
            width: parent.width; height: 34
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; right: saveBtn.visible ? saveBtn.left : sortBtn.left; rightMargin: 12 }
                elide: Text.ElideRight
                text: (page.heading !== "" ? page.heading + " · " : page.hasText ? "Resultados · " : "Todas as músicas · ")
                      + model.count.toLocaleString(Qt.locale(), "f", 0) + (model.count === 1 ? " música" : " músicas")
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
            }
            FlatButton {
                id: saveBtn
                anchors { right: sortBtn.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                visible: page.fullQuery !== ""
                text: "Salvar busca"; color: hovered ? Theme.hover : "transparent"
                onClicked: page.saveSmart(page.fullQuery, page.effectiveSort)
            }
            Rectangle {
                id: sortBtn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: sortRow.implicitWidth + 20; height: 32; radius: Theme.radius
                color: sortMa.pressed ? Theme.pressed : sortMa.containsMouse ? Theme.hover : "transparent"
                Row {
                    id: sortRow
                    anchors.centerIn: parent; spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "sort"; size: 16 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: page.sortLabel(page.effectiveSort); color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "pan-down"; size: 12 }
                }
                MouseArea { id: sortMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sortMenu.openUnder(sortBtn) }
            }
        }
        // Search scopes (AdwToggleGroup-like chips), shown while searching.
        Flow {
            visible: page.hasText
            width: parent.width; spacing: 6
            Repeater {
                model: page.scopes
                Rectangle {
                    required property var modelData
                    readonly property bool on: page.scope === modelData.k
                    width: chip.implicitWidth + 24; height: 30; radius: 15
                    color: on ? Theme.accent : chipMa.containsMouse ? Theme.pressed : Theme.hover
                    Text { id: chip; anchors.centerIn: parent; text: modelData.t; color: parent.on ? "white" : Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1; font.weight: Font.DemiBold }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { page.scope = modelData.k; page.run() } }
                }
            }
        }
    }
    SortMenu {
        id: sortMenu
        options: page.hasText ? page.sortOptions : page.sortOptions.slice(1)
        current: page.effectiveSort
        onChosen: (k) => { page.sort = k; page.userSorted = k !== ""; page.run() }
    }

    ListView {
        id: lv
        anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom; topMargin: 8 }
        clip: true
        model: model
        reuseItems: true
        cacheBuffer: 540
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: 18

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
            required property string quality
            readonly property var track: ({ id: Number(trackId), title: title, artist: artist, album: album,
                                            albumId: Number(albumId) >= 0 ? Number(albumId) : null, duration: Number(duration),
                                            starred: starred, cover: cover, coverBig: coverBig, url: url, remote: remote, quality: quality })
            width: lv.width; height: 54
            readonly property bool first: index === 0
            readonly property bool last: index === model.count - 1
            // One opaque card per row; only the first/last rows round their outer corners.
            Rectangle {
                anchors { fill: parent; leftMargin: page.side; rightMargin: page.rightSide }
                color: Theme.cardBg
                radius: d.first || d.last ? Theme.cardRadius : 0
                Rectangle { visible: d.first && !d.last; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: Theme.cardRadius; color: Theme.cardBg }
                Rectangle { visible: d.last && !d.first; anchors { left: parent.left; right: parent.right; top: parent.top } height: Theme.cardRadius; color: Theme.cardBg }
                TrackRow {
                    anchors.fill: parent
                    radius: parent.radius
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

    FastScroll {
        id: fast
        anchors { right: parent.right; top: lv.top; bottom: lv.bottom; rightMargin: 4 }
        view: lv
        sections: page.sections
        labelAt: function (i) { return model.sectionAt(i) }
    }

    Column {
        anchors.centerIn: parent
        visible: page.loaded && model.count === 0
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "search"; size: 96; color: Theme.dimFg }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.hasText ? "Nenhum resultado" : "Nenhuma música aqui"
            color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize + 1; font.weight: Theme.headingWeight
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.hasText
            text: "Dica: artista:nome, genero:rock, ano:2010-2019, album:nome"
            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
        }
    }
}
