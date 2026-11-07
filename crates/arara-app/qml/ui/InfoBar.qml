import QtQuick
import AraraStyle

// "Sobre" side bar for an album or an artist: photo, Wikipedia text, facts
// from MusicBrainz, library stats, top songs and albums they appear on.
Rectangle {
    id: bar
    property string kind: "artist"     // "artist" | "album"
    property var subject: null         // album or artist object from the grids
    property var info: null            // albumInfoJson / artistInfoJson
    property var online: null
    property bool loading: false
    property bool onlineOff: false
    property int playingId: -1
    // Inline in a page (album left column): no header, cover or own scrolling;
    // the height follows the content.
    property bool embedded: false
    implicitHeight: embedded ? col.height + 8 : 0
    signal closeRequested()
    signal playTracks(var tracks, int index)
    signal openAlbum(var album)
    signal openLink(string url)
    signal refreshOnline()
    signal openFolder(string url)

    color: embedded ? "transparent" : Theme.viewBg
    clip: !embedded
    Rectangle { visible: !bar.embedded; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.border }

    // Swallow clicks so they don't reach the page underneath.
    MouseArea { enabled: !bar.embedded; anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = false }

    readonly property bool isArtist: kind === "artist"
    readonly property var stats: info && info.stats ? info.stats : ({})
    property bool expanded: false
    onSubjectChanged: { expanded = false; flick.contentY = 0 }

    function months() { return ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"] }
    function niceDate(d) {
        if (!d) return ""
        var m = String(d).match(/^(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?/)
        if (!m) return String(d)
        if (m[3]) return Number(m[3]) + " de " + months()[Number(m[2]) - 1] + " de " + m[1]
        if (m[2]) return months()[Number(m[2]) - 1] + " de " + m[1]
        return m[1]
    }
    function unixDate(s) {
        if (!s) return ""
        var d = new Date(Number(s) * 1000)
        return d.getDate() + " de " + months()[d.getMonth()] + " de " + d.getFullYear()
    }
    function longDur(ms) {
        var min = Math.round(Number(ms || 0) / 60000), h = Math.floor(min / 60)
        return h > 0 ? h + " h " + (min % 60) + " min" : min + " min"
    }
    function countries(c) {
        var map = { BR: "Brasil", US: "Estados Unidos", GB: "Reino Unido", XW: "Mundial", XE: "Europa", JP: "Japão", DE: "Alemanha", FR: "França", PT: "Portugal", CA: "Canadá", AR: "Argentina", MX: "México", ES: "Espanha", IT: "Itália", AU: "Austrália", KR: "Coreia do Sul" }
        return map[c] || c || ""
    }

    readonly property var genres: {
        var out = [], seen = {}
        function add(g) { var k = String(g).toLowerCase(); if (!seen[k]) { seen[k] = 1; out.push(g) } }
        if (online && online.genres) online.genres.forEach(add)
        if (info && info.genres) info.genres.forEach(add)
        return out.slice(0, 6)
    }

    readonly property string subtitle: {
        if (!subject) return ""
        var p = []
        if (isArtist) {
            if (online && online.type) p.push(online.type)
            if (online && (online.beginArea || online.country)) p.push(online.beginArea || online.country)
            if (online && online.disambiguation && p.length === 0) p.push(online.disambiguation)
        } else {
            p.push(online && online.type ? online.type + (online.secondary && online.secondary.length ? " " + online.secondary.join(", ").toLowerCase() : "") : "Álbum")
            if (subject.artist) p.push(subject.artist)
            var y = online && (online.firstDate || online.date) ? String(online.firstDate || online.date).slice(0, 4) : subject.year
            if (y) p.push(y)
        }
        return p.join(" · ")
    }

    readonly property var factRows: {
        var r = []
        if (!online) return r
        function kv(k, v, link) { if (v !== undefined && v !== null && String(v) !== "") r.push({ k: k, v: v, link: link || "" }) }
        if (isArtist) {
            kv("Tipo", online.type)
            kv(online.person ? "Nascimento" : "Formação", niceDate(online.begin) + (online.beginArea ? (online.begin ? " · " : "") + online.beginArea : ""))
            if (online.end) kv(online.person ? "Falecimento" : "Fim", niceDate(online.end))
            else if (online.begin && !online.person) kv("Em atividade", "Sim")
            kv("País", online.country)
            kv("Descrição", online.disambiguation)
        } else {
            // The original release date, like Wikipedia; a later edition's date only if different.
            kv("Lançamento", niceDate(online.firstDate || online.date))
            if (online.firstDate && online.date && online.date.slice(0, 4) !== online.firstDate.slice(0, 4)) kv("Esta edição", niceDate(online.date))
            kv("Gravadora", online.label)
            kv("Catálogo", online.catalog)
            kv("País", countries(online.country))
            var fm = { "Digital Media": "Digital", "Vinyl": "Vinil", '12" Vinyl': "Vinil 12″", "Cassette": "Fita cassete", "CD": "CD" }
            kv("Formato", online.media && online.media.length ? (online.media.length > 1 ? online.media.length + " × " : "") + (fm[online.media[0]] || online.media[0]) : "")
            kv("Código de barras", online.barcode)
        }
        return r
    }

    readonly property var libraryRows: {
        var r = []
        if (!info) return r
        function kv(k, v, link) { if (v !== undefined && v !== null && String(v) !== "" && v !== 0) r.push({ k: k, v: v, link: link || "" }) }
        if (isArtist) {
            var albums = subject ? subject.albums : 0
            kv("Álbuns", albums)
            kv("Músicas", stats.tracks)
            kv("Duração total", stats.durationMs ? longDur(stats.durationMs) : "")
            kv("Anos", stats.firstYear ? (stats.lastYear && stats.lastYear !== stats.firstYear ? stats.firstYear + " – " + stats.lastYear : stats.firstYear) : "")
            kv("Reproduções", stats.plays)
            kv("Favoritas", stats.starred)
            kv("Última vez", unixDate(stats.lastPlayed))
        } else {
            var f = info.fields || {}
            kv("Faixas", stats.tracks)
            if (stats.discs > 1) kv("Discos", stats.discs)
            kv("Duração", stats.durationMs ? longDur(stats.durationMs) : "")
            kv("Gravadora", online && online.label ? "" : f.label)
            kv("Copyright", f.copyright)
            kv("Compositores", info.composers && info.composers.length ? info.composers.join(", ") : "")
            kv("Qualidade", (info.grade ? info.grade + " · " : "") + (info.qualities || []).slice(0, 2).join(" / "))
            kv("Reproduções", stats.plays)
            kv("Adicionado em", unixDate(stats.addedAt))
            kv("Pasta", info.folder ? String(info.folder).split(/[\\/]/).filter(function (x) { return x !== "" }).pop() : "", "folder")
        }
        return r
    }

    // Header bar (AdwHeaderBar of a sidebar pane).
    Item {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 1 }
        visible: !bar.embedded
        height: bar.embedded ? 0 : Theme.headerHeight
        Text {
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            text: bar.isArtist ? "Sobre o artista" : "Sobre o álbum"
            color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize + 0.5; font.weight: Font.Bold
        }
        FlatButton {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            icon: "close"; onClicked: bar.closeRequested()
        }
    }

    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; leftMargin: 1 }
        clip: !bar.embedded
        interactive: !bar.embedded
        contentHeight: col.height + 40
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: bar.embedded ? 0 : 18; width: flick.width - (bar.embedded ? 0 : 36)
            y: bar.embedded ? 0 : 4
            spacing: 18

            Column {
                width: parent.width
                spacing: 8
                CoverArt {
                    visible: !bar.embedded
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: bar.isArtist ? 132 : Math.min(220, parent.width); height: width
                    radius: bar.isArtist ? width / 2 : Math.max(3, Math.round(width * Theme.coverRound))
                    decode: 440
                    source: bar.isArtist ? (bar.online && bar.online.photo ? bar.online.photo : bar.subject ? bar.subject.cover || "" : "")
                                         : (bar.subject ? bar.subject.coverBig || bar.subject.cover || "" : "")
                }
                Text {
                    visible: !bar.embedded
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: bar.subject ? ((bar.isArtist ? bar.subject.name : bar.subject.title) || "") : ""
                    color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 2; font.weight: Theme.titleWeight
                }
                Text {
                    visible: text !== "" && !bar.embedded
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: bar.subtitle
                    color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
                }
                Flow {
                    visible: bar.genres.length > 0
                    width: parent.width
                    spacing: 6
                    topPadding: 4
                    Repeater {
                        model: bar.genres
                        Rectangle {
                            required property var modelData
                            height: 24; radius: 12
                            width: gt.implicitWidth + 20
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.22 : 0.12)
                            Text { id: gt; anchors.centerIn: parent; text: modelData; color: Theme.accentFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5; font.weight: Font.DemiBold }
                        }
                    }
                }
            }

            // Wikipedia text.
            Column {
                visible: !!(bar.online && bar.online.wiki)
                width: parent.width
                spacing: 6
                Text {
                    id: wikiText
                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: bar.expanded ? 400 : 7
                    elide: Text.ElideRight
                    lineHeight: 1.15
                    text: bar.online && bar.online.wiki ? bar.online.wiki.text : ""
                    color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize
                }
                Row {
                    spacing: 14
                    Text {
                        visible: wikiText.truncated || bar.expanded
                        text: bar.expanded ? "Mostrar menos" : "Mostrar mais"
                        color: Theme.accentFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 0.5; font.weight: Font.DemiBold
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.expanded = !bar.expanded }
                    }
                    Text {
                        text: "Wikipédia ↗"
                        color: Theme.accentFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 0.5; font.weight: Font.DemiBold
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.openLink(bar.online.wiki.url) }
                    }
                }
            }

            InfoSection {
                width: parent.width
                title: "Detalhes"
                rows: bar.factRows
                busy: bar.loading
                busyText: bar.isArtist ? "Buscando o artista no MusicBrainz…" : "Buscando o álbum no MusicBrainz…"
                note: bar.online ? "Fontes: MusicBrainz" + (bar.online.wiki ? " e Wikipédia" : "") : ""
            }
            Text {
                visible: !bar.loading && !bar.online
                width: parent.width; wrapMode: Text.Wrap
                text: bar.onlineOff ? "A busca de informações online está desligada nas Preferências."
                                    : "Nada encontrado no MusicBrainz. Sem internet ou nome diferente do cadastro."
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }

            // Artist: most played songs, playable.
            Column {
                visible: bar.isArtist && !!bar.info && !!bar.info.top && bar.info.top.length > 0
                width: parent.width
                spacing: 8
                Text { leftPadding: 4; text: bar.stats.plays > 0 ? "Mais tocadas" : "Músicas"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize + 0.5; font.weight: Theme.headingWeight }
                Rectangle {
                    width: parent.width; height: topCol.height
                    radius: Theme.cardRadius; color: Theme.cardBg
                    border.color: Theme.border; border.width: Theme.dark ? 0 : 1
                    clip: true
                    Column {
                        id: topCol
                        width: parent.width
                        Repeater {
                            model: bar.info && bar.info.top ? bar.info.top : []
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: topCol.width; height: 52
                                color: tm.containsMouse ? Theme.hover : "transparent"
                                Rectangle { visible: index > 0; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 60 } height: 1; color: Theme.border; opacity: 0.6 }
                                CoverArt { id: tc; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36; decode: 72; source: modelData.cover || "" }
                                Column {
                                    anchors { left: tc.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    Text { width: parent.width; elide: Text.ElideRight; text: modelData.title; color: modelData.id === bar.playingId ? Theme.accentFg : Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                                    Text { width: parent.width; elide: Text.ElideRight; text: modelData.album || ""; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5 }
                                }
                                MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bar.playTracks(bar.info.top, index) }
                            }
                        }
                    }
                }
            }

            InfoSection {
                width: parent.width
                title: "Na sua biblioteca"
                rows: bar.libraryRows
                onActivated: (row) => { if (row.link === "folder") bar.openFolder(bar.info.folderUrl) }
            }

            // Artist: albums by others they appear on.
            Column {
                visible: bar.isArtist && !!bar.info && !!bar.info.appearsOn && bar.info.appearsOn.length > 0
                width: parent.width
                spacing: 8
                Text { leftPadding: 4; text: "Aparece em"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize + 0.5; font.weight: Theme.headingWeight }
                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: bar.info && bar.info.appearsOn ? bar.info.appearsOn : []
                        Column {
                            required property var modelData
                            width: (col.width - 12) / 2
                            spacing: 4
                            CoverArt { width: parent.width; height: width; decode: 200; source: modelData.cover || ""
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.openAlbum(modelData) } }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.title; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 0.5 }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.artist || ""; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5 }
                        }
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 8
                FlatButton {
                    visible: !!bar.online && !!bar.online.link
                    text: "Abrir no MusicBrainz"; color: Theme.hover
                    onClicked: bar.openLink(bar.online.link)
                }
                FlatButton {
                    visible: !bar.onlineOff
                    text: bar.loading ? "Buscando…" : "Atualizar"; color: Theme.hover
                    onClicked: if (!bar.loading) bar.refreshOnline()
                }
            }
        }
    }
}
