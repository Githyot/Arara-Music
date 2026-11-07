import QtQuick
import AraraStyle

// "Retrospectiva": how much you listened, to whom and when, for a week, a
// month, a year or all time, like Spotify Wrapped, Apple Music Replay and
// YouTube Music Recap. Everything comes from the local listening history.
Item {
    id: page
    property bool tracking: true
    signal playTrack(var id)
    signal playTop(var ids)
    signal openArtist(var id)
    signal openAlbum(var id)
    signal turnOn()

    property string mode: "month"     // week | month | year | all
    property int offset: 0            // 0 = current period, -1 = the one before…
    property var recap: ({})
    property real prevTotal: 0
    property real firstListen: 0
    readonly property var range: rangeFor(mode, offset)
    readonly property bool empty: !(recap.totalMs > 0)
    readonly property int side: Math.max(24, (width - 1000) / 2)
    readonly property real cw: width - 2 * side
    readonly property bool twoCols: cw >= 680

    onModeChanged: reload()
    onOffsetChanged: reload()

    function reload() {
        firstListen = library.firstListen()
        var r = rangeFor(mode, offset)   // not `range`: its binding may not have updated yet
        recap = JSON.parse(library.recapJson(r.from, r.to))
        // The current period isn't over yet: compare with the same stretch of the previous one.
        var prevTo = r.prevTo
        if (offset === 0 && r.prevFrom >= 0) prevTo = Math.min(r.prevTo, r.prevFrom + (Math.floor(Date.now() / 1000) - r.from))
        prevTotal = r.prevFrom >= 0 ? library.listenedMs(r.prevFrom, prevTo) : 0
        flick.contentY = 0
    }
    function setMode(m) { offset = 0; mode = m }

    // ---------- formatting ----------
    readonly property var months: ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
    readonly property var monthsShort: ["jan.", "fev.", "mar.", "abr.", "maio", "jun.", "jul.", "ago.", "set.", "out.", "nov.", "dez."]
    readonly property var weekdays: ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
    function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }
    function num(n) { return Number(n || 0).toLocaleString(Qt.locale("pt_BR"), "f", 0) }
    function mins(ms) { return Math.round((ms || 0) / 60000) }
    function minsText(ms) { var m = mins(ms); return num(m) + (m === 1 ? " minuto" : " minutos") }
    function shortMins(ms) { var m = mins(ms); return m < 1 && ms > 0 ? "< 1 min" : num(m) + " min" }
    function hoursText(ms) {
        var m = mins(ms), h = Math.floor(m / 60), r = m % 60
        if (h === 0) return r + " min"
        return h + (h === 1 ? " hora" : " horas") + (r > 0 ? " e " + r + " min" : "")
    }
    function plays(n) { return num(n) + (n === 1 ? " vez" : " vezes") }
    function dateText(d) { return d.getDate() + " de " + monthsShort[d.getMonth()] + " de " + d.getFullYear() }
    function parseDay(s) { var p = s.split("-"); return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])) }

    // ---------- periods ----------
    function rangeFor(m, off) {
        var now = new Date(), y = now.getFullYear(), mo = now.getMonth()
        var f, t, pf, label, phrase, prevPhrase
        if (m === "week") {
            var d = new Date(y, mo, now.getDate())
            var dow = (d.getDay() + 6) % 7          // weeks start on Monday
            f = new Date(d.getFullYear(), d.getMonth(), d.getDate() - dow + 7 * off)
            t = new Date(f.getFullYear(), f.getMonth(), f.getDate() + 7)
            pf = new Date(f.getFullYear(), f.getMonth(), f.getDate() - 7)
            var e = new Date(t.getFullYear(), t.getMonth(), t.getDate() - 1)
            label = f.getMonth() === e.getMonth()
                ? f.getDate() + " a " + e.getDate() + " de " + months[e.getMonth()]
                : f.getDate() + " de " + monthsShort[f.getMonth()] + " a " + e.getDate() + " de " + monthsShort[e.getMonth()]
            if (e.getFullYear() !== y) label += " de " + e.getFullYear()
            phrase = off === 0 ? "nesta semana" : off === -1 ? "na semana passada" : "de " + label
            prevPhrase = off === 0 ? "a semana passada" : "a semana anterior"
        } else if (m === "month") {
            f = new Date(y, mo + off, 1); t = new Date(y, mo + off + 1, 1); pf = new Date(y, mo + off - 1, 1)
            label = cap(months[f.getMonth()]) + (f.getFullYear() !== y ? " de " + f.getFullYear() : "")
            phrase = "em " + months[f.getMonth()] + (f.getFullYear() !== y ? " de " + f.getFullYear() : "")
            prevPhrase = months[pf.getMonth()]
        } else if (m === "year") {
            f = new Date(y + off, 0, 1); t = new Date(y + off + 1, 0, 1); pf = new Date(y + off - 1, 0, 1)
            label = String(f.getFullYear()); phrase = "em " + label; prevPhrase = String(pf.getFullYear())
        } else {
            return { from: 0, to: 0, prevFrom: -1, prevTo: 0, label: "Desde o começo", phrase: "desde que você começou", prevPhrase: "", start: null, end: now }
        }
        return { from: Math.floor(f.getTime() / 1000), to: Math.floor(t.getTime() / 1000),
                 prevFrom: Math.floor(pf.getTime() / 1000), prevTo: Math.floor(f.getTime() / 1000),
                 label: label, phrase: phrase, prevPhrase: prevPhrase, start: f, end: t }
    }
    readonly property bool atNow: offset === 0
    readonly property bool canGoBackInTime: mode !== "all" && firstListen > 0 && range.from > firstListen

    // Bars over time: days of the week / month, months of the year, years.
    function timeline() {
        var days = recap.days || [], r = range, vals = [], labels = [], i
        if (mode === "week" || mode === "month") {
            var n = Math.round((r.end - r.start) / 86400000)
            for (i = 0; i < n; i++) { vals.push(0); labels.push(mode === "week" ? ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"][i] : (i === 0 || (i + 1) % 5 === 0 ? String(i + 1) : "")) }
            days.forEach(function (x) { var k = Math.round((parseDay(x.d) - r.start) / 86400000); if (k >= 0 && k < n) vals[k] += x.ms })
        } else if (mode === "year") {
            for (i = 0; i < 12; i++) { vals.push(0); labels.push(["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"][i]) }
            days.forEach(function (x) { vals[parseDay(x.d).getMonth()] += x.ms })
        } else {
            var y0 = days.length ? parseDay(days[0].d).getFullYear() : new Date().getFullYear(), y1 = new Date().getFullYear()
            for (i = y0; i <= y1; i++) { vals.push(0); labels.push(String(i)) }
            days.forEach(function (x) { vals[parseDay(x.d).getFullYear() - y0] += x.ms })
        }
        return { values: vals, labels: labels }
    }
    function peakIndex(a) { var b = -1, v = 0; for (var i = 0; i < (a || []).length; i++) if (a[i] > v) { v = a[i]; b = i } return b }
    function busiestDay() { var b = null; (recap.days || []).forEach(function (x) { if (!b || x.ms > b.ms) b = x }); return b }
    // A short "listening personality", Wrapped style.
    function personality() {
        var h = recap.hours || [], tot = recap.totalMs || 1, night = 0, morning = 0
        for (var i = 0; i < 24; i++) { if (i >= 21 || i < 5) night += h[i]; if (i >= 5 && i < 12) morning += h[i] }
        var top = (recap.topArtists || [])[0], share = top ? top.ms / tot : 0
        if (top && share >= 0.3) return { title: "Fã de carteirinha", text: Math.round(share * 100) + "% do seu tempo foi com " + top.name + "." }
        if (night / tot >= 0.4) return { title: "Coruja da noite", text: Math.round(night / tot * 100) + "% do que você ouviu foi depois das 21h." }
        if (morning / tot >= 0.45) return { title: "Trilha do amanhecer", text: Math.round(morning / tot * 100) + "% do que você ouviu foi de manhã." }
        if ((recap.artists || 0) >= 25 && share < 0.12) return { title: "Explorador de sons", text: num(recap.artists) + " artistas diferentes, sem nenhum dominar." }
        if ((recap.topGenres || []).length >= 4) return { title: "Ouvido eclético", text: "Você passeou por " + recap.topGenres.length + " gêneros ou mais." }
        return { title: "Ouvinte fiel", text: "Você volta sempre para as suas favoritas." }
    }
    function deltaText() {
        if (mode === "all" || prevTotal <= 0 || !(recap.totalMs > 0)) return ""
        var p = Math.round((recap.totalMs - prevTotal) / prevTotal * 100)
        var than = offset !== 0 ? " que " + range.prevPhrase
                 : mode === "week" ? " que até agora na semana passada"
                 : mode === "month" ? " que até o dia " + new Date().getDate() + " de " + range.prevPhrase
                 : " que em " + range.prevPhrase + " até esta data"
        if (p === 0) return "O mesmo tanto" + than
        return (p > 0 ? "↑ " + p + "% a mais" : "↓ " + (-p) + "% a menos") + than
    }

    // ======================================================================
    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.height + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: page.side; y: 24
            width: page.cw
            spacing: 18

            // ---------- title + period picker ----------
            Item {
                width: parent.width; height: titleCol.height
                Column {
                    id: titleCol
                    width: parent.width - (playBtn.visible ? playBtn.width + 12 : 0)
                    spacing: 4
                    Row {
                        spacing: 10
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "recap"; size: 22; color: Theme.accentFg }
                        Text { text: "Retrospectiva"; color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize; font.weight: Theme.titleWeight }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: "Quanto você ouviu, de quem e quando. Tudo fica só neste computador."
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                }
                FlatButton {
                    id: playBtn
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: !page.empty
                    suggested: true; icon: "play"; text: "Assistir retrospectiva"
                    onClicked: story.open()
                }
            }

            Item {
                width: parent.width; height: 36
                // segmented control (Adwaita linked toggle buttons)
                Rectangle {
                    id: seg
                    height: 34; width: segRow.width + 6
                    radius: Theme.material ? height / 2 : Theme.radius + 2
                    color: Theme.hover
                    Row {
                        id: segRow
                        x: 3; anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: [{ k: "week", t: "Semana" }, { k: "month", t: "Mês" }, { k: "year", t: "Ano" }, { k: "all", t: "Sempre" }]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: page.mode === modelData.k
                                height: 28; width: segText.implicitWidth + 28
                                radius: Theme.material ? height / 2 : Theme.radius
                                color: on ? (Theme.material ? Theme.selected : Theme.cardBg) : segMa.containsMouse ? Theme.hover : "transparent"
                                border.width: on && !Theme.material ? 1 : 0; border.color: Theme.border
                                Behavior on color { ColorAnimation { duration: Theme.ms(120) } }
                                Text {
                                    id: segText; anchors.centerIn: parent
                                    text: modelData.t; color: Theme.fg
                                    font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: parent.on ? Font.Bold : Font.Normal
                                }
                                MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.setMode(modelData.k) }
                            }
                        }
                    }
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    visible: page.mode !== "all"
                    FlatButton { icon: "back"; tip: "Período anterior"; enabled: page.canGoBackInTime; opacity: enabled ? 1 : 0.35; onClicked: page.offset-- }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(implicitWidth, 120); horizontalAlignment: Text.AlignHCenter
                        text: page.range.label; color: Theme.fg
                        font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
                    }
                    FlatButton { icon: "pan-end"; tip: "Próximo período"; enabled: !page.atNow; opacity: enabled ? 1 : 0.35; onClicked: page.offset++ }
                }
            }

            // ---------- empty ----------
            Column {
                visible: page.empty
                width: parent.width
                topPadding: 60
                spacing: 10
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "recap"; size: 72; color: Theme.dimFg; opacity: 0.6 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.tracking ? "Nada ouvido " + page.range.phrase : "O registro do que você ouve está desligado"
                    color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 2; font.weight: Theme.headingWeight
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 460); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    text: page.tracking ? "Toque algumas músicas e volte aqui. O tempo que você passa com cada artista, álbum e música aparece nesta tela, como no Spotify Wrapped."
                                        : "Ligue para o Arara contar o tempo que você passa com cada artista. Nada sai do seu computador."
                    color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
                }
                FlatButton { visible: !page.tracking; anchors.horizontalCenter: parent.horizontalCenter; suggested: true; text: "Ligar o registro"; onClicked: page.turnOn() }
            }

            // ---------- hero ----------
            Rectangle {
                id: hero
                visible: !page.empty
                width: parent.width; height: page.twoCols ? 250 : 400
                radius: Theme.cardRadius + 4
                clip: true
                readonly property var topArtist: (page.recap.topArtists || [])[0] || null
                readonly property string blur: topArtist && topArtist.cover ? library.coverBlur(topArtist.coverBig || topArtist.cover) : ""
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.darker(Theme.accent, 1.1) }
                    GradientStop { position: 1; color: Qt.darker(Theme.accent, 2.4) }
                }
                Image {
                    anchors.fill: parent; source: hero.blur; fillMode: Image.PreserveAspectCrop
                    asynchronous: true; cache: false; opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.15) }
                    }
                }
                // big number
                Column {
                    anchors { left: parent.left; leftMargin: 28; top: parent.top; topMargin: 26 }
                    width: page.twoCols ? parent.width * 0.58 : parent.width - 56
                    spacing: 2
                    Text { text: "Você ouviu " + page.range.phrase; color: Qt.rgba(1, 1, 1, 0.85); font.family: Theme.font; font.pointSize: Theme.fontSize + 1 }
                    Row {
                        spacing: 10
                        Text {
                            id: bigNum
                            text: page.num(page.mins(page.recap.totalMs))
                            color: "white"; font.family: Theme.displayFont; font.pointSize: 54; font.weight: Font.Black
                        }
                        Text {
                            anchors.baseline: bigNum.baseline
                            text: page.mins(page.recap.totalMs) === 1 ? "minuto" : "minutos"
                            color: "white"; font.family: Theme.displayFont; font.pointSize: 20; font.weight: Font.Bold
                        }
                    }
                    Text {
                        text: page.hoursText(page.recap.totalMs) + " de música · " + page.plays(page.recap.plays) + " dando play"
                        color: Qt.rgba(1, 1, 1, 0.85); font.family: Theme.font; font.pointSize: Theme.fontSize
                        width: parent.width; elide: Text.ElideRight
                    }
                    Item { width: 1; height: 10 }
                    Rectangle {
                        visible: page.deltaText() !== ""
                        height: 26; width: deltaT.implicitWidth + 22; radius: 13
                        color: Qt.rgba(1, 1, 1, 0.18)
                        Text { id: deltaT; anchors.centerIn: parent; text: page.deltaText(); color: "white"; font.family: Theme.font; font.pointSize: Theme.fontSize - 1; font.weight: Font.DemiBold }
                    }
                }
                // number one artist
                Column {
                    visible: hero.topArtist !== null
                    anchors { right: parent.right; rightMargin: 32; bottom: page.twoCols ? undefined : parent.bottom; bottomMargin: 22
                              verticalCenter: page.twoCols ? parent.verticalCenter : undefined }
                    spacing: 6
                    CoverArt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: page.twoCols ? 140 : 96; height: width; radius: width / 2
                        source: hero.topArtist ? hero.topArtist.coverBig || hero.topArtist.cover : ""
                        MouseArea { anchors.fill: parent; cursorShape: hero.topArtist && hero.topArtist.id ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (hero.topArtist && hero.topArtist.id) page.openArtist(hero.topArtist.id) }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SEU ARTISTA Nº 1"; color: Qt.rgba(1, 1, 1, 0.8); font.family: Theme.font; font.pointSize: Theme.fontSize - 2; font.weight: Font.Bold; font.letterSpacing: 1 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, 220); elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                        text: hero.topArtist ? hero.topArtist.name : ""; color: "white"; font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 1; font.weight: Font.Bold
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: hero.topArtist ? page.shortMins(hero.topArtist.ms) : ""; color: Qt.rgba(1, 1, 1, 0.8); font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                }
            }

            // ---------- numbers ----------
            Flow {
                visible: !page.empty
                width: parent.width
                spacing: 10
                readonly property int cols: page.cw >= 680 ? 5 : page.cw >= 460 ? 3 : 2
                readonly property real tileW: (width - (cols - 1) * spacing) / cols
                Repeater {
                    model: [
                        { v: page.recap.tracks, t: page.recap.tracks === 1 ? "música diferente" : "músicas diferentes" },
                        { v: page.recap.artists, t: page.recap.artists === 1 ? "artista" : "artistas" },
                        { v: page.recap.albums, t: page.recap.albums === 1 ? "álbum" : "álbuns" },
                        { v: page.recap.daysActive, t: page.recap.daysActive === 1 ? "dia ouvindo" : "dias ouvindo" },
                        { v: page.recap.streak, t: page.recap.streak === 1 ? "dia seguido, recorde" : "dias seguidos, recorde" }
                    ]
                    Rectangle {
                        required property var modelData
                        width: parent.tileW; height: 76
                        radius: Theme.cardRadius
                        color: Theme.cardBg; border.color: Theme.border; border.width: Theme.material ? 0 : 1
                        Column {
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            spacing: 0
                            Text { text: page.num(modelData.v); color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize; font.weight: Font.Bold }
                            Text { width: parent.parent.width - 24; elide: Text.ElideRight; text: modelData.t; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                        }
                    }
                }
            }

            // ---------- top artists / top songs ----------
            Grid {
                visible: !page.empty
                width: parent.width
                columns: page.twoCols ? 2 : 1
                columnSpacing: 18; rowSpacing: 18
                readonly property real colW: page.twoCols ? (width - columnSpacing) / 2 : width

                Card {
                    width: parent.colW
                    title: "Top artistas"
                    Repeater {
                        model: (page.recap.topArtists || []).slice(0, 5)
                        RankRow {
                            required property var modelData
                            required property int index
                            rank: index + 1; round: true
                            item: modelData; maxMs: page.recap.topArtists[0].ms
                            sub: page.shortMins(modelData.ms) + " · " + page.plays(modelData.plays)
                            clickable: !!modelData.id
                            onActivated: page.openArtist(modelData.id)
                        }
                    }
                }
                Card {
                    width: parent.colW
                    title: "Top músicas"
                    action: (page.recap.topTracks || []).length > 1 ? "Tocar todas" : ""
                    onActionClicked: page.playTop((page.recap.topTracks || []).filter(function (t) { return t.id }).map(function (t) { return t.id }))
                    Repeater {
                        model: (page.recap.topTracks || []).slice(0, 5)
                        RankRow {
                            required property var modelData
                            required property int index
                            rank: index + 1
                            item: modelData; maxMs: page.recap.topTracks[0].ms
                            line2: modelData.artist
                            sub: page.plays(modelData.plays) + " · " + page.shortMins(modelData.ms)
                            clickable: !!modelData.id
                            onActivated: page.playTrack(modelData.id)
                        }
                    }
                }
            }

            // ---------- top albums ----------
            Card {
                visible: !page.empty && (page.recap.topAlbums || []).length > 0
                width: parent.width
                title: "Top álbuns"
                Flow {
                    width: parent.width
                    spacing: 14
                    readonly property int n: Math.max(2, Math.min(5, Math.floor((width + spacing) / (130 + spacing))))
                    readonly property real tile: (width - (n - 1) * spacing) / n
                    Repeater {
                        model: (page.recap.topAlbums || []).slice(0, parent.n)
                        Column {
                            required property var modelData
                            required property int index
                            width: parent.tile
                            spacing: 4
                            CoverArt {
                                width: parent.width; height: width
                                source: modelData.coverBig || modelData.cover
                                hovered: alMa.containsMouse
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; margins: 8 }
                                    width: 26; height: 26; radius: 13; color: Qt.rgba(0, 0, 0, 0.55)
                                    Text { anchors.centerIn: parent; text: index + 1; color: "white"; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.Bold }
                                }
                                MouseArea { id: alMa; anchors.fill: parent; hoverEnabled: true; cursorShape: modelData.id ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (modelData.id) page.openAlbum(modelData.id) }
                            }
                            Text { width: parent.width; text: modelData.name; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                            Text { width: parent.width; text: modelData.artist + " · " + page.shortMins(modelData.ms); elide: Text.ElideRight; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                        }
                    }
                }
            }

            // ---------- when ----------
            Grid {
                visible: !page.empty
                width: parent.width
                columns: page.twoCols ? 2 : 1
                columnSpacing: 18; rowSpacing: 18
                readonly property real colW: page.twoCols ? (width - columnSpacing) / 2 : width

                Card {
                    id: tlCard
                    width: parent.colW
                    title: page.mode === "week" ? "Dia a dia" : page.mode === "month" ? "Dia a dia" : page.mode === "year" ? "Mês a mês" : "Ano a ano"
                    readonly property var tl: page.timeline()
                    Bars { width: parent.width; values: tlCard.tl.values; labels: tlCard.tl.labels }
                    Text {
                        readonly property var b: page.busiestDay()
                        visible: !!b
                        width: parent.width; wrapMode: Text.Wrap
                        text: b ? "Dia mais musical: " + page.dateText(page.parseDay(b.d)) + ", com " + page.hoursText(b.ms) + "." : ""
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                }
                Card {
                    width: parent.colW
                    title: "Que horas você ouve"
                    Bars {
                        width: parent.width
                        values: page.recap.hours || []
                        labels: ["0h", "", "", "", "", "", "6h", "", "", "", "", "", "12h", "", "", "", "", "", "18h", "", "", "", "", "23h"]
                    }
                    Text {
                        readonly property int h: page.peakIndex(page.recap.hours)
                        readonly property int w: page.peakIndex(page.recap.weekdays)
                        visible: h >= 0
                        width: parent.width; wrapMode: Text.Wrap
                        text: "Seu horário favorito é por volta das " + h + "h" + (w >= 0 ? ", e o dia da semana em que mais ouve é " + page.weekdays[w] + (w === 0 || w === 6 ? "." : "-feira.") : ".")
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                }
            }

            // ---------- genres + personality ----------
            Grid {
                visible: !page.empty
                width: parent.width
                columns: page.twoCols ? 2 : 1
                columnSpacing: 18; rowSpacing: 18
                readonly property real colW: page.twoCols ? (width - columnSpacing) / 2 : width

                Card {
                    width: parent.colW
                    title: "Gêneros"
                    Text {
                        visible: (page.recap.topGenres || []).length === 0
                        width: parent.width; wrapMode: Text.Wrap
                        text: "As músicas ouvidas não têm gênero nas tags."
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
                    }
                    Repeater {
                        model: (page.recap.topGenres || []).slice(0, 5)
                        Column {
                            required property var modelData
                            width: parent.width
                            spacing: 4
                            readonly property real share: modelData.ms / Math.max(1, page.recap.totalMs)
                            Item {
                                width: parent.width; height: gName.implicitHeight
                                Text { id: gName; text: modelData.name; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                                Text { anchors.right: parent.right; text: Math.max(1, Math.round(parent.parent.share * 100)) + "%"; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                            }
                            Rectangle {
                                width: parent.width; height: 8; radius: 4; color: Theme.hover
                                Rectangle { width: Math.max(8, parent.width * parent.parent.share); height: parent.height; radius: 4; color: Theme.accent }
                            }
                        }
                    }
                }
                Card {
                    id: pCard
                    width: parent.colW
                    title: "Seu jeito de ouvir"
                    readonly property var p: page.personality()
                    Text { width: parent.width; wrapMode: Text.Wrap; text: pCard.p.title; color: Theme.accentFg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize; font.weight: Font.Bold }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: pCard.p.text; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                    Item { width: 1; height: 4 }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        visible: (page.recap.newArtists || []).length > 0
                        text: "Novas descobertas " + page.range.phrase + ":"
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                    Flow {
                        width: parent.width; spacing: 12
                        visible: (page.recap.newArtists || []).length > 0
                        Repeater {
                            model: (page.recap.newArtists || []).slice(0, 6)
                            Column {
                                required property var modelData
                                width: 64; spacing: 3
                                CoverArt {
                                    width: 56; height: 56; radius: 28; anchors.horizontalCenter: parent.horizontalCenter
                                    source: modelData.cover
                                    MouseArea { anchors.fill: parent; cursorShape: modelData.id ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (modelData.id) page.openArtist(modelData.id) }
                                }
                                Text { width: parent.width; text: modelData.name; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
                            }
                        }
                    }
                }
            }

            Text {
                visible: !page.empty
                width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                text: "Conta como “vez” quando você ouve 30 segundos ou mais, como no Spotify. Os minutos contam só o tempo realmente ouvido."
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2
            }
        }
    }

    RecapStory {
        id: story
        page: page
    }

    // ---------- building blocks ----------
    component Card: Rectangle {
        id: card
        property string title: ""
        property string action: ""
        signal actionClicked()
        default property alias content: inner.data
        height: inner.height + 32
        radius: Theme.cardRadius
        color: Theme.cardBg
        border.color: Theme.border; border.width: Theme.material ? 0 : 1
        Column {
            id: inner
            x: 16; y: 14
            width: card.width - 32
            spacing: 10
            Item {
                width: parent.width; height: Math.max(cardTitle.implicitHeight, card.action ? 28 : 0)
                Text { id: cardTitle; anchors.verticalCenter: parent.verticalCenter; text: card.title; color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight }
                FlatButton { visible: card.action !== ""; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: card.action; size: 28; color: Theme.hover; onClicked: card.actionClicked() }
            }
        }
    }

    component RankRow: Item {
        id: rr
        property int rank: 1
        property var item: ({})
        property real maxMs: 1
        property bool round: false
        property string line2: ""
        property string sub: ""
        property bool clickable: false
        signal activated()
        width: parent ? parent.width : 0
        height: 52
        Rectangle { anchors { fill: parent; leftMargin: -6; rightMargin: -6 } radius: Theme.radius; color: rrMa.containsMouse && rr.clickable ? Theme.hover : "transparent" }
        Text {
            id: rankT
            width: 22; anchors.verticalCenter: parent.verticalCenter
            text: rr.rank; horizontalAlignment: Text.AlignHCenter
            color: rr.rank === 1 ? Theme.accentFg : Theme.dimFg
            font.family: Theme.displayFont; font.pointSize: Theme.headingSize; font.weight: Font.Bold
        }
        CoverArt {
            id: rrCover
            anchors { left: rankT.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            width: 42; height: 42; radius: rr.round ? 21 : Math.max(3, Math.round(42 * Theme.coverRound))
            source: rr.item.cover || ""
        }
        Column {
            anchors { left: rrCover.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 3
            Text { width: parent.width; text: rr.item.name + (rr.line2 ? "  ·  " + rr.line2 : ""); elide: Text.ElideRight; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
            Rectangle {
                width: parent.width; height: 4; radius: 2; color: Theme.hover
                Rectangle { width: Math.max(4, parent.width * rr.item.ms / Math.max(1, rr.maxMs)); height: 4; radius: 2; color: Theme.accent; opacity: rr.rank === 1 ? 1 : 0.6 }
            }
            Text { width: parent.width; text: rr.sub; elide: Text.ElideRight; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
        }
        MouseArea { id: rrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: rr.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (rr.clickable) rr.activated() }
    }

    // Simple bar chart; the tallest bar is highlighted, hover shows the time.
    component Bars: Item {
        id: bars
        property var values: []
        property var labels: []
        property color barColor: Theme.accent
        property color textColor: Theme.dimFg
        height: 130
        readonly property real maxV: Math.max(1, Math.max.apply(null, values && values.length ? values : [0]))
        readonly property int peak: page.peakIndex(values)
        readonly property int n: values ? values.length : 0
        readonly property real gap: n > 20 ? 2 : 6
        readonly property real bw: n ? (width - (n - 1) * gap) / n : 0
        Repeater {
            model: bars.n
            Item {
                required property int index
                x: index * (bars.bw + bars.gap); width: bars.bw; height: bars.height
                readonly property real v: bars.values[index] || 0
                Rectangle {
                    anchors { bottom: parent.bottom; bottomMargin: 18; horizontalCenter: parent.horizontalCenter }
                    width: parent.width; radius: Math.min(4, width / 2)
                    height: Math.max(v > 0 ? 3 : 2, (bars.height - 40) * v / bars.maxV)
                    color: v > 0 ? bars.barColor : Theme.hover
                    opacity: index === bars.peak ? 1 : barMa.containsMouse ? 0.85 : 0.45
                    Behavior on height { NumberAnimation { duration: Theme.ms(300); easing.type: Easing.OutCubic } }
                }
                Text {
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    text: bars.labels[index] || ""; color: bars.textColor
                    font.family: Theme.font; font.pointSize: Theme.fontSize - 3
                }
                Rectangle {
                    visible: barMa.containsMouse && v > 0
                    z: 2
                    anchors { bottom: parent.bottom; bottomMargin: 22 + (bars.height - 40) * v / bars.maxV; horizontalCenter: parent.horizontalCenter }
                    width: tipT.implicitWidth + 12; height: 20; radius: 4; color: Theme.toastBg
                    Text { id: tipT; anchors.centerIn: parent; text: page.shortMins(v); color: Theme.toastFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
                }
                MouseArea { id: barMa; anchors.fill: parent; hoverEnabled: true }
            }
        }
    }
}
