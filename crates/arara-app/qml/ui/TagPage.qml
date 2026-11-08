import QtQuick
import AraraStyle

// "Similares": everything in the library (local and synced servers) that
// shares a genre chip, plus artists MusicBrainz files under it.
Flickable {
    id: page
    property string tag: ""
    property string fromName: ""        // artist/album the chip was on
    property var data: null             // library.tagJson
    property var online: null           // tagOnline: { artists: [...] }
    property bool onlineLoading: false
    property bool onlineOff: false
    property var knownArtists: []       // whole library, to tell online hits we already have
    property int playingId: -1
    signal openArtist(var artist)
    signal openAlbum(var album)
    signal play(var tracks, int index)
    signal menuRequested(var track, real x, real y)
    signal starToggled(var track, bool starred)
    signal openLink(string url)

    clip: true
    contentHeight: col.height + 56
    boundsBehavior: Flickable.StopAtBounds

    readonly property var artists: data ? data.artists : []
    readonly property var albums: data ? data.albums : []
    readonly property var tracks: data ? data.tracks : []
    property int shownTracks: 20
    onDataChanged: { shownTracks = 20; contentY = 0 }

    // Online hits split: ones in the library join "Artistas", the rest go to "Para descobrir".
    readonly property var libIndex: {
        var m = {}
        for (var i = 0; i < knownArtists.length; i++) m[String(knownArtists[i].name).toLowerCase()] = knownArtists[i]
        return m
    }
    readonly property var allArtists: {
        var out = artists.slice(), seen = {}
        out.forEach(function (a) { seen[a.id] = 1 })
        if (online && online.artists) online.artists.forEach(function (o) {
            var hit = libIndex[String(o.name).toLowerCase()]
            if (hit && !seen[hit.id] && hit.name !== page.fromName) { seen[hit.id] = 1; out.push(hit) }
        })
        return out
    }
    readonly property var discover: {
        if (!online || !online.artists) return []
        var lib = libIndex
        return online.artists.filter(function (o) { return !lib[String(o.name).toLowerCase()] && o.name !== page.fromName }).slice(0, 24)
    }

    function areaPt(a) {
        var m = { "Brazil": "Brasil", "United States": "Estados Unidos", "United Kingdom": "Reino Unido", "Germany": "Alemanha", "France": "França",
                  "Japan": "Japão", "Spain": "Espanha", "Italy": "Itália", "Canada": "Canadá", "Mexico": "México", "Norway": "Noruega",
                  "Sweden": "Suécia", "Ireland": "Irlanda", "Australia": "Austrália", "South Korea": "Coreia do Sul", "Netherlands": "Holanda",
                  "Belgium": "Bélgica", "Finland": "Finlândia", "Denmark": "Dinamarca", "Iceland": "Islândia", "Colombia": "Colômbia" }
        return m[a] || a || ""
    }
    function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }

    Column {
        id: col
        width: Math.min(page.width - 48, 1100)
        x: (page.width - width) / 2
        y: 24
        spacing: 26

        // ---- header ----
        Column {
            width: parent.width
            spacing: 4
            Text { text: "SIMILARES"; color: Theme.accentFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2; font.weight: Font.Bold; font.letterSpacing: 0.6 }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: page.tag.length <= 3 ? page.tag.toUpperCase() : page.tag.charAt(0).toUpperCase() + page.tag.slice(1)
                color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize; font.weight: Theme.titleWeight
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: !page.data ? "" : (page.fromName !== "" ? "Na linha de " + page.fromName : "Na sua biblioteca") + " · "
                      + [page.plural(page.allArtists.length, "artista", "artistas"),
                         page.plural(page.data.albumTotal, "álbum", "álbuns"),
                         page.plural(page.data.trackTotal, "música", "músicas")].join(" · ")
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
            }
            Item { width: 1; height: 8 }
            Row {
                spacing: 8
                visible: page.tracks.length > 0
                FlatButton { text: "Reproduzir"; suggested: true; onClicked: page.play(page.tracks, 0) }
                FlatButton {
                    text: "Aleatório"; color: Theme.hover
                    onClicked: {
                        var t = page.tracks.slice()
                        for (var i = t.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var x = t[i]; t[i] = t[j]; t[j] = x }
                        page.play(t, 0)
                    }
                }
            }
        }

        // ---- empty state ----
        Column {
            visible: !!page.data && page.allArtists.length === 0 && page.albums.length === 0 && page.tracks.length === 0
            width: parent.width
            spacing: 6
            topPadding: 24
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "genre"; size: 48; color: Theme.dimFg }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: "Nada mais com “" + page.tag + "” na sua biblioteca"
                color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: "O Arara procura pelo gênero gravado nas músicas e pelo que já veio do MusicBrainz."
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
            }
        }

        // ---- artists ----
        Column {
            visible: page.allArtists.length > 0
            width: parent.width
            spacing: 12
            Text { text: "Artistas"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight }
            Flow {
                id: artistFlow
                width: parent.width
                readonly property int tile: 112
                readonly property int columns: Math.max(2, Math.floor((width + 16) / (tile + 52)))
                readonly property int cell: Math.floor((width - (columns - 1) * 16) / columns)
                spacing: 16
                Repeater {
                    model: page.allArtists
                    Item {
                        required property var modelData
                        width: artistFlow.cell; height: artistFlow.tile + 50
                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: artistFlow.tile; height: width
                                CoverArt { anchors.fill: parent; radius: width / 2; decode: 224; source: modelData.cover || ""; hovered: arm.containsMouse }
                                Text {
                                    anchors.centerIn: parent; visible: !modelData.cover
                                    text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                                    color: Theme.dimFg; font.family: Theme.font; font.pointSize: 32; font.weight: Font.Bold
                                }
                            }
                            Text {
                                width: artistFlow.cell; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: modelData.name; color: Theme.fg
                                font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
                            }
                            Text {
                                width: artistFlow.cell; horizontalAlignment: Text.AlignHCenter
                                text: page.plural(modelData.albums, "álbum", "álbuns"); color: Theme.dimFg
                                font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5
                            }
                        }
                        MouseArea { id: arm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openArtist(modelData) }
                    }
                }
            }
        }

        // ---- albums ----
        Column {
            visible: page.albums.length > 0
            width: parent.width
            spacing: 12
            Text { text: "Álbuns"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight }
            Flow {
                id: albumFlow
                width: parent.width
                readonly property int gap: Theme.compact ? 14 : 20
                readonly property int columns: Math.max(2, Math.floor((width + gap) / (Theme.tileMin - 20 + gap)))
                readonly property int tile: Math.floor((width - (columns - 1) * gap) / columns)
                spacing: gap
                Repeater {
                    model: page.albums
                    Item {
                        required property var modelData
                        width: albumFlow.tile; height: albumFlow.tile + 52
                        Column {
                            width: parent.width
                            spacing: 6
                            CoverArt { width: albumFlow.tile; height: width; decode: albumFlow.tile; source: modelData.cover; hovered: alm.containsMouse }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.title; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: (modelData.artist || "") + (modelData.year ? " · " + modelData.year : ""); color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                        }
                        MouseArea { id: alm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openAlbum(modelData) }
                    }
                }
            }
        }

        // ---- songs ----
        Column {
            visible: page.tracks.length > 0
            width: parent.width
            spacing: 12
            Text { text: "Músicas"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight }
            Rectangle {
                width: parent.width; height: songCol.height
                radius: Theme.cardRadius; color: Theme.cardBg
                border.color: Theme.border; border.width: Theme.dark ? 0 : 1
                clip: true
                Column {
                    id: songCol
                    width: parent.width
                    Repeater {
                        model: page.tracks.slice(0, page.shownTracks)
                        TrackRow {
                            required property var modelData
                            required property int index
                            width: songCol.width
                            track: modelData
                            number: index
                            showArt: true
                            playing: modelData.id === page.playingId
                            onActivated: page.play(page.tracks, index)
                            onMenuRequested: (t, x, y) => page.menuRequested(t, x, y)
                            onStarToggled: (t, s) => page.starToggled(t, s)
                        }
                    }
                }
            }
            FlatButton {
                visible: page.tracks.length > page.shownTracks
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Mostrar mais músicas"; color: Theme.hover
                onClicked: page.shownTracks += 40
            }
        }

        // ---- online ----
        Column {
            visible: !page.onlineOff && (page.onlineLoading || page.discover.length > 0)
            width: parent.width
            spacing: 12
            Text { text: "Para descobrir"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight }
            Text {
                visible: page.onlineLoading
                text: "Buscando artistas de “" + page.tag + "” no MusicBrainz…"
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 0.5
            }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: page.discover
                    Rectangle {
                        required property var modelData
                        height: 52; radius: Theme.cardRadius
                        width: Math.min(parent.width, Math.max(dn.implicitWidth, dd.implicitWidth) + 28)
                        color: dm.containsMouse ? Theme.hover : Theme.cardBg
                        border.color: Theme.border; border.width: Theme.dark ? 0 : 1
                        Column {
                            anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            Text { id: dn; width: parent.width; elide: Text.ElideRight; text: modelData.name; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                            Text {
                                id: dd; width: parent.width; elide: Text.ElideRight
                                text: [modelData.type, page.areaPt(modelData.area)].filter(function (x) { return !!x }).join(" · ") || "MusicBrainz"
                                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5
                            }
                        }
                        MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openLink(modelData.link) }
                    }
                }
            }
            Text {
                visible: page.discover.length > 0
                text: "Fonte: MusicBrainz. Clique para abrir a página do artista."
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5
            }
        }
    }
}
