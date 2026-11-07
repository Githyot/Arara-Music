import QtQuick
import AraraStyle

// Song details (like Apple Music's song page): cover, title, artist · album ·
// date, play, lyrics, credits (file tags + MusicBrainz), details, library
// stats and file properties.
Flickable {
    id: page
    property var info: null          // trackInfoJson()
    property var online: null        // MusicBrainz answer, or null
    property bool loading: false
    property bool playing: false
    property var knownArtists: []    // lower-case names of library artists (credits link to them)
    signal play(var track)
    signal openLyrics(var track)
    signal openAlbum(var track)
    signal openArtistByName(string name)
    signal starToggled(var track, bool starred)
    signal menuRequested(var track, real x, real y)
    signal editRequested(var track)
    signal showInFolder(var track)
    signal refreshOnline(var track)
    signal openLink(string url)

    clip: true
    contentHeight: body.height + 56
    boundsBehavior: Flickable.StopAtBounds

    readonly property var file: info && info.file ? info.file : ({})
    readonly property var fields: file.fields || ({})
    readonly property var audio: file.audio || ({})

    function months() { return ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"] }
    // "2016-02-14" → "14 de fevereiro de 2016"; "2016" stays.
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
    function dur(ms) {
        var s = Math.round(Number(ms || 0) / 1000), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60)
        s = s % 60
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s
    }
    function size(b) {
        b = Number(b || 0)
        if (b <= 0) return ""
        return b >= 1048576 ? (b / 1048576).toFixed(1).replace(".", ",") + " MB" : Math.round(b / 1024) + " KB"
    }
    function releaseDate() {
        var d = fields.releaseDate || fields.originalDate || (online && online.firstDate) || fields.recordingDate || ""
        var y = info && info.year ? String(info.year) : ""
        // An edited year wins over a full date that no longer matches it.
        if (y && String(d).slice(0, 4) !== y) d = y
        return niceDate(d)
    }

    // Credits: file tags first, then MusicBrainz, merged by name.
    readonly property var credits: {
        var out = [], seen = {}
        function add(c) {
            var key = String(c.name).toLowerCase()
            if (seen[key] !== undefined) {
                var o = out[seen[key]], roles = o.role.split(", ")
                String(c.role).split(", ").forEach(function (r) { if (roles.indexOf(r) < 0) roles.push(r) })
                o.role = roles.join(", ")
                return
            }
            seen[key] = out.length
            out.push({ name: c.name, role: c.role, inLibrary: knownArtists.indexOf(key) >= 0 })
        }
        var tagC = file.credits || []
        if (info && info.edited) tagC = tagC.filter(function (c) { return c.role !== "Artista" && c.role !== "Participação" })
        if (info && info.edited && info.artist) add({ name: info.artist, role: "Artista" })
        tagC.forEach(add)
        if (online && online.credits) online.credits.forEach(add)
        if (out.length === 0 && info && info.artist) add({ name: info.artist, role: "Artista" })
        if (info && info.composer && !out.some(function (c) { return c.role.indexOf("Composição") >= 0 }))
            info.composer.split(/[;\/]/).forEach(function (n) { if (n.trim()) add({ name: n.trim(), role: "Composição" }) })
        return out
    }

    readonly property var detailRows: {
        if (!info) return []
        var r = []
        function kv(k, v, link) { if (v !== undefined && v !== null && String(v) !== "") r.push({ k: k, v: v, link: link || "" }) }
        kv("Álbum", info.album, info.albumId !== null && info.albumId !== undefined ? "album" : "")
        var tn = info.trackNo || fields.track, tt = fields.trackTotal
        kv("Faixa", tn ? tn + (tt ? " de " + tt : "") : "")
        var dn = info.discNo || fields.disc, dt = fields.discTotal
        if (dn && (dt > 1 || dn > 1)) kv("Disco", dn + (dt ? " de " + dt : ""))
        kv("Lançamento", releaseDate())
        var g = info.genre || ""
        if (online && online.genres && online.genres.length) {
            var extra = online.genres.filter(function (x) { return g.toLowerCase().indexOf(x.toLowerCase()) < 0 })
            if (extra.length) g = g ? g + " · " + extra.slice(0, 2).join(", ") : extra.slice(0, 3).join(", ")
        }
        kv("Gênero", g)
        kv("Duração", dur(info.duration))
        kv("BPM", fields.bpm)
        kv("Tom", fields.key)
        var langs = { por: "Português", pt: "Português", eng: "Inglês", en: "Inglês", spa: "Espanhol", es: "Espanhol", fra: "Francês", fre: "Francês", fr: "Francês",
                      ita: "Italiano", it: "Italiano", deu: "Alemão", ger: "Alemão", de: "Alemão", jpn: "Japonês", ja: "Japonês", kor: "Coreano", ko: "Coreano", zxx: "Instrumental" }
        kv("Idioma", fields.language ? (langs[String(fields.language).toLowerCase()] || fields.language) : "")
        kv("ISRC", fields.isrc || (online ? online.isrc : ""))
        kv("Gravadora", fields.label)
        kv("Editora", fields.publisher)
        kv("Copyright", fields.copyright)
        kv("Comentário", fields.comment)
        return r
    }

    readonly property var libraryRows: {
        if (!info) return []
        var r = []
        r.push({ k: "Reproduções", v: info.plays > 0 ? info.plays + (info.plays === 1 ? " vez" : " vezes") : "Nunca tocada" })
        if (info.lastPlayed) r.push({ k: "Última vez", v: unixDate(info.lastPlayed) })
        if (info.addedAt) r.push({ k: "Adicionada em", v: unixDate(info.addedAt) })
        r.push({ k: "Favorita", v: info.starred ? "Sim" : "Não" })
        r.push({ k: "Letra", v: info.hasLyrics ? "Salva" : "Ainda não baixada" })
        if (info.gain !== null && info.gain !== undefined) r.push({ k: "ReplayGain", v: (info.gain > 0 ? "+" : "") + Number(info.gain).toFixed(1).replace(".", ",") + " dB" })
        return r
    }

    readonly property var fileRows: {
        if (!info) return []
        var r = []
        function kv(k, v, link) { if (v !== undefined && v !== null && String(v) !== "" && v !== 0) r.push({ k: k, v: v, link: link || "" }) }
        kv("Qualidade", (info.quality ? info.quality + " · " : "") + (info.qualityDetail || ""))
        kv("Taxa de bits", audio.bitrate ? audio.bitrate + " kbps" : "")
        kv("Amostragem", audio.sampleRate ? (audio.sampleRate / 1000).toString().replace(".", ",") + " kHz" : "")
        kv("Resolução", audio.bitDepth ? audio.bitDepth + " bits" : "")
        kv("Canais", audio.channels === 1 ? "Mono" : audio.channels === 2 ? "Estéreo" : audio.channels ? audio.channels + " canais" : "")
        kv("Tamanho", size(audio.size || info.size))
        kv("Codificador", fields.encoder)
        if (info.local) kv("Local", info.path, "folder")
        else kv("Origem", "Servidor de música")
        return r
    }

    Column {
        id: body
        width: Math.min(page.width - 48, 680)
        x: (page.width - width) / 2
        y: 28
        spacing: 22

        // ---- header ----
        Column {
            width: parent.width
            spacing: 10
            CoverArt {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(240, body.width); height: width
                decode: 480
                source: page.info ? page.info.coverBig || page.info.cover || "" : ""
            }
            Item { width: 1; height: 4 }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: page.info ? page.info.title : ""
                color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize; font.weight: Theme.titleWeight
            }
            // Artist · Album · Date, each part clickable.
            Flow {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitW, parent.width)
                property real implicitW: a1.implicitWidth + d1.implicitWidth + a2.implicitWidth + d2.implicitWidth + a3.implicitWidth + 4
                spacing: 0
                Text {
                    id: a1; text: page.info ? page.info.artist : ""
                    color: m1.containsMouse ? Theme.accentFg : Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize + 1
                    MouseArea { id: m1; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openArtistByName(page.info.artist) }
                }
                Text { id: d1; visible: a2.text !== ""; text: "  ·  "; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize + 1 }
                Text {
                    id: a2; text: page.info && page.info.album ? page.info.album : ""
                    color: m2.containsMouse ? Theme.accentFg : Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize + 1
                    MouseArea { id: m2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openAlbum(page.info) }
                }
                Text { id: d2; visible: a3.text !== ""; text: "  ·  "; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize + 1 }
                Text { id: a3; text: page.releaseDate(); color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize + 1 }
            }
            Item { width: 1; height: 6 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                FlatButton { text: page.playing ? "Tocando agora" : "Reproduzir"; suggested: true; size: 38; onClicked: page.play(page.info) }
                FlatButton {
                    icon: page.info && page.info.starred ? "star" : "unstar"; size: 38; color: Theme.hover
                    iconColor: page.info && page.info.starred ? Theme.accentFg : undefined
                    onClicked: { var s = !page.info.starred; page.starToggled(page.info, s); var i = page.info; i.starred = s; page.info = null; page.info = i }
                }
                FlatButton {
                    icon: "edit"; size: 38; color: Theme.hover; tip: "Editar informações"
                    onClicked: page.editRequested(page.info)
                }
                FlatButton {
                    id: moreBtn; icon: "more"; size: 38; color: Theme.hover
                    onClicked: { var p = moreBtn.mapToItem(null, 0, moreBtn.height + 4); page.menuRequested(page.info, p.x, p.y) }
                }
            }
        }

        // ---- lyrics row ----
        Rectangle {
            width: parent.width; height: 52
            radius: Theme.cardRadius
            color: lm.containsMouse ? Qt.darker(Theme.cardBg, Theme.dark ? 0.85 : 1.03) : Theme.cardBg
            border.color: Theme.border; border.width: Theme.dark ? 0 : 1
            Icon { id: li; name: "lyrics"; size: 18; anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter } }
            Text { anchors { left: li.right; leftMargin: 14; verticalCenter: parent.verticalCenter } text: "Ver letra"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize + 1 }
            Icon { name: "go-next"; size: 14; color: Theme.dimFg; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } }
            MouseArea { id: lm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openLyrics(page.info) }
        }

        InfoSection {
            width: parent.width
            title: "Créditos"
            mode: "people"
            rows: page.credits
            busy: page.loading
            busyText: "Buscando créditos no MusicBrainz…"
            note: page.online ? "Fontes: tags do arquivo e MusicBrainz" : (page.file.credits && page.file.credits.length ? "Fonte: tags do arquivo" : "")
            onActivated: (row) => page.openArtistByName(row.name)
        }
        InfoSection {
            width: parent.width
            title: "Samples"
            rows: page.online && page.online.samples ? page.online.samples.map(function (s) { return { k: s.artist || "", v: s.title || "" } }) : []
        }
        InfoSection {
            width: parent.width
            title: "Sobre a música"
            rows: page.detailRows
            onActivated: (row) => { if (row.link === "album") page.openAlbum(page.info) }
        }
        InfoSection { width: parent.width; title: "Na sua biblioteca"; rows: page.libraryRows }
        InfoSection {
            width: parent.width
            title: "Arquivo"
            rows: page.fileRows
            onActivated: (row) => { if (row.link === "folder") page.showInFolder(page.info) }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            FlatButton {
                visible: !!page.online && !!page.online.link
                text: "Abrir no MusicBrainz"; color: Theme.hover
                onClicked: page.openLink(page.online.link)
            }
            FlatButton {
                text: page.loading ? "Buscando…" : "Atualizar dados online"; color: Theme.hover
                onClicked: if (!page.loading) page.refreshOnline(page.info)
            }
        }
    }
}
