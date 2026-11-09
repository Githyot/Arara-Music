import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtMultimedia
import Qt.labs.settings
import AraraCypher
import io.github.arara as Arara
import AraraCypher.Audio

// Visualização de uma cifra: seções com os acordes, tom e transposição, e um
// menu de opções (rolagem automática, colunas, capotraste, afinação, mostrar
// tabs e batidas, metrônomo no BPM da música e pedal passador).
Rectangle {
    id: page
    property var song
    property int semitones: 0
    // Dentro do modo Estudar do Arara Music: a barra de cima e a letra ficam
    // com a tela de estudo, e a parte que está tocando fica em destaque.
    property bool embedded: false
    // Faixa da biblioteca do Arara que combina com esta cifra (null se não tem):
    // dá para abrir o modo Estudar com a música tocando junto.
    readonly property var libraryTrack: !embedded && song && Examples.trackFinder ? Examples.trackFinder(song) : null
    property int activeSection: -1
    property bool followSection: true
    property bool concealActive: false     // treino de ouvido
    signal sectionClicked(int index)
    onActiveSectionChanged: if (embedded && followSection && activeSection >= 0) scrollToSection.restart()
    Timer {
        id: scrollToSection
        interval: 30
        onTriggered: {
            var item = secRepeater.itemAt(page.activeSection)
            if (!item) return
            var y = item.mapToItem(content, 0, 0).y + content.y - 12
            var max = Math.max(0, flick.contentHeight - flick.height)
            if (y < flick.contentY + 20 || y > flick.contentY + flick.height * 0.55) {
                scrollAnim.to = Math.max(0, Math.min(max, y))
                scrollAnim.restart()
            }
        }
    }
    NumberAnimation { id: scrollAnim; target: flick; property: "contentY"; duration: 450; easing.type: Easing.OutCubic }
    // Capotraste e afinação escolhidos aqui: mudam as formas, não o som.
    readonly property int songCapo: song && song.capo ? song.capo : 0
    property int capo: songCapo
    property int tuning: 0              // semitons abaixo do padrão (0, 1, 2)
    readonly property int shift: semitones + (songCapo - capo) + tuning

    // Preferências da tela (valem para todas as músicas).
    Settings {
        id: prefs
        category: "musica"
        property int columns: 1
        property bool showTabs: true
        property bool showStrums: true
        property int scrollSpeed: 3
        property bool pedal: true
    }
    function restoreDefaults() {
        prefs.columns = 1; prefs.showTabs = true; prefs.showStrums = true
        prefs.scrollSpeed = 3; prefs.pedal = true
        capo = songCapo; tuning = 0; semitones = 0
        Theme.chordZoom = 1
        viewMode = "all"; fullScore = false
        scrolling = false; metroVisible = false; metro.running = false
        metro.bpm = songBpm
    }

    // ---- Rolagem automática ----
    property bool scrolling: false
    readonly property var scrollSpeeds: [0, 8, 14, 22, 32, 45, 62, 85]   // pixels por segundo
    Timer {
        interval: 30
        repeat: true
        running: page.scrolling
        onTriggered: {
            var max = flick.contentHeight - flick.height
            if (flick.contentY >= max) { page.scrolling = false; return }
            flick.contentY = Math.min(max, flick.contentY + page.scrollSpeeds[prefs.scrollSpeed] * 0.03)
        }
    }

    // ---- Pedal passador / teclado: Page Down, seta para baixo ou direita avançam. ----
    function page_(dir) {
        var max = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(max, flick.contentY + dir * flick.height * 0.8))
    }
    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onPressed: (e) => {
        if (!prefs.pedal) return
        if (e.key === Qt.Key_PageDown || e.key === Qt.Key_Down || e.key === Qt.Key_Right) { page_(1); e.accepted = true }
        else if (e.key === Qt.Key_PageUp || e.key === Qt.Key_Up || e.key === Qt.Key_Left) { page_(-1); e.accepted = true }
    }

    // ---- Letra (LRCLIB) ----
    // Baixada quando o usuário pede; nas músicas dele fica salva na biblioteca.
    property var lyrics: song && song.lyrics ? { plain: song.lyrics, synced: song.syncedLyrics || [] } : null
    property string lyricsStatus: ""
    function fetchLyrics() {
        if (!song) return
        lyricsStatus = "Buscando a letra no LRCLIB..."
        var url = "https://lrclib.net/api/search?track_name=" + encodeURIComponent(song.title)
                + (song.artist ? "&artist_name=" + encodeURIComponent(song.artist) : "")
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) {
                page.lyricsStatus = "Não consegui falar com o LRCLIB" + (xhr.status ? " (erro " + xhr.status + ")" : "") + ". Veja a internet e tente de novo."
                return
            }
            var r = JSON.parse(Arara.CypherLibrary.pickLyrics(xhr.responseText, page.song.title, page.song.artist || ""))
            if (!r.found) { page.lyricsStatus = "O LRCLIB não tem a letra dessa música. Confira o título e o artista no editor."; return }
            if (r.instrumental) { page.lyricsStatus = "O LRCLIB diz que essa música é instrumental."; return }
            page.song.lyrics = r.plain
            page.song.syncedLyrics = r.synced
            page.lyrics = { plain: r.plain, synced: r.synced }
            if (page.song.id) {
                Arara.CypherLibrary.save(JSON.stringify(page.song))
                page.lyricsStatus = "Letra salva na sua cópia."
            } else {
                page.lyricsStatus = "Para guardar a letra, toque em Editar uma cópia."
            }
        }
        xhr.open("GET", url)
        xhr.setRequestHeader("Lrclib-Client", "AraraCypher " + Arara.CypherMusic.version + " (https://github.com/Githyot/Arara-Cypher)")
        xhr.send()
    }
    // Acompanhar a letra sincronizada: um relógio desde o começo da música.
    property bool lyricsPlaying: false
    property real lyricsT0: 0
    property real lyricsNow: 0
    property int lyricsLine: -1
    Timer {
        interval: 100
        repeat: true
        running: page.lyricsPlaying
        onTriggered: {
            page.lyricsNow = (Date.now() - page.lyricsT0) / 1000
            var s = page.lyrics ? page.lyrics.synced : []
            var i = -1
            for (var k = 0; k < s.length; ++k) if (s[k].t <= page.lyricsNow) i = k
            page.lyricsLine = i
            if (s.length && page.lyricsNow > s[s.length - 1].t + 10) page.lyricsPlaying = false
        }
    }
    function toggleLyrics() {
        if (lyricsPlaying) { lyricsPlaying = false; return }
        lyricsT0 = Date.now() - Math.max(0, lyricsNow) * 1000
        lyricsPlaying = true
    }

    // ---- Metrônomo no BPM da música ----
    readonly property int songBpm: {
        if (song && song.bpm) return song.bpm
        if (song && song.strums) for (var i = 0; i < song.strums.length; ++i) if (song.strums[i].bpm) return song.strums[i].bpm
        return 80
    }
    property bool metroVisible: false
    QtObject {
        id: metro
        property int bpm: page.songBpm
        property bool running: false
        property real t0: 0
        property int beat: -1
    }

    Timer {
        interval: 5
        repeat: true
        running: metro.running
        onTriggered: {
            var n = Math.floor((Date.now() - metro.t0) / (60000 / metro.bpm))
            if (n !== metro.beat) {
                metro.beat = n
                metroSound.play(n % 4 === 0)
            }
        }
    }
    function toggleMetro() {
        if (metro.running) { metro.running = false; return }
        metro.t0 = Date.now()
        metro.beat = -1
        metro.running = true
    }
    property string viewMode: "all"   // "all" | "names" | "diagram" | "big" | "tab" | "score" | "lesson"
    // Na aula, as partes sem tab aparecem como na visualização Tab.
    readonly property string chordMode: viewMode === "lesson" ? "tab" : viewMode
    property bool fullScore: false     // partitura da música inteira, em linhas
    readonly property bool showFullScore: viewMode === "score" && fullScore
    readonly property real zoom: Theme.chordZoom

    // ---- Editar a tab aqui mesmo ----
    // Tocar numa casa abre o painel (casa, dedo, tocar ou não a corda);
    // tocar numa seta troca o golpe daquele tempo. Muda a forma do acorde
    // (song.voicings) e a batida da parte, e salva na biblioteca.
    property bool editingTab: false
    property int rev: 0
    property string editStatus: ""
    onEditingTabChanged: editStatus = ""
    function persist() {
        rev++
        if (song.id) { Arara.CypherLibrary.save(JSON.stringify(song)); editStatus = "Salvo." }
        else editStatus = "Mudou só nesta tela. Para guardar, toque em Editar uma cópia."
    }

    // Batidas usadas em alguma parte da música, na ordem.
    readonly property var usedStrums: {
        var out = []
        if (!song || !song.strums) return out
        for (var i = 0; i < song.strums.length; ++i) {
            var used = false
            for (var j = 0; j < song.sections.length; ++j)
                if ((song.sections[j].strum || 0) === i) used = true
            if (used) out.push(song.strums[i])
        }
        return out
    }

    // Partitura da música inteira em blocos: compassos de acordes (um por
    // acorde) e, no meio, os riffs/solos colados como tab.
    readonly property var scoreBlocks: {
        var out = []
        if (!song) return out
        var n = 1
        var cur = null
        for (var i = 0; i < song.sections.length; ++i) {
            var sec = song.sections[i]
            var strum = Examples.strumOf(song, sec)
            for (var j = 0; j < sec.chords.length; ++j) {
                if (!cur) { cur = { tab: "", measures: [] }; out.push(cur) }
                cur.measures.push({
                    chord: Examples.chordName(sec.chords[j]),
                    voicing: Examples.voicing(song, sec.chords[j]),
                    pattern: strum ? strum.pattern : ["D"],
                    number: n++,
                    label: j === 0 ? sec.name : "",
                    repeat: j === sec.chords.length - 1 && sec.repeat > 1 ? sec.repeat : 0
                })
            }
            if (sec.tab && sec.tab.length > 0) {
                cur = null
                var events = JSON.parse(Arara.CypherMusic.parseTab(sec.tab))
                if (events.length === 0) continue
                var bars = events.filter(function (e) { return e.bar }).length
                out.push({ tab: sec.tab, measures: [], start: n,
                           label: sec.name + (sec.repeat > 1 ? " (" + sec.repeat + "×)" : "") })
                n += bars + 1
            }
        }
        return out
    }
    signal back()
    signal edit()

    signal setAll(bool open)

    // "D · D U · U D U" -> setas para o resumo das batidas.
    function arrows(pattern) {
        return pattern.map(function (p) {
            return Examples.strokeArrow(p)
        }).join(" ")
    }
    // Acordes da parte. A tab manda: com tab, só os marcados nela
    // (Acorde neste toque), na ordem; sem tab, os acordes da parte.
    function partChords(sec) {
        if (!sec) return []
        if (!sec.tab) return sec.chords || []
        var out = []
        JSON.parse(Arara.CypherMusic.tabModel(sec.tab)).forEach(function (sys) {
            (sys.chords || []).slice().sort(function (a, b) { return a.at - b.at }).forEach(function (c) {
                if (c.name && out.indexOf(c.name) < 0) out.push(c.name)
            })
        })
        return out
    }
    function chordList(sec) {
        var names = partChords(sec).map(function (c) { return t(Examples.chordName(c)) })
        var s = names.join("  ")
        if (sec.tab) s += (s ? "  · " : "") + "tab"
        if (!s && sec.note) s = sec.note
        return s
    }
    // Nome de uma parte anterior com os mesmos acordes e a mesma tab, ou "".
    function sameAs(i) {
        if (!song) return ""
        var a = song.sections[i]
        if (a.chords.length === 0 && !a.tab) return ""
        for (var j = 0; j < i; ++j) {
            var b = song.sections[j]
            if (b.chords.join(" ") === a.chords.join(" ") && (b.tab || "") === (a.tab || "")
                    && (b.strum || 0) === (a.strum || 0))
                return b.name
        }
        return ""
    }

    color: Theme.window

    function t(chord) { return Arara.CypherMusic.transposeChord(chord, shift) }

    // ---- Tocar junto: o microfone ouve o acorde e a música anda sozinha ----
    Mic { id: mic }
    property bool playAlong: false
    onPlayAlongChanged: { mic.active = playAlong; if (playAlong) { playIdx = 0; heard = ""; streak = 0; goToSection() } }
    onVisibleChanged: if (!visible) playAlong = false
    // Sequência dos acordes na ordem em que se toca (com as repetições).
    readonly property var playSeq: {
        var out = []
        if (!song) return out
        for (var i = 0; i < song.sections.length; ++i) {
            var cs = partChords(song.sections[i])
            for (var r = 0; r < Math.max(1, song.sections[i].repeat || 1); ++r)
                for (var k = 0; k < cs.length; ++k) out.push({ sec: i, chord: cs[k] })
        }
        return out
    }
    property int playIdx: 0
    property string heard: ""          // acorde ouvido agora (nome na tela)
    property int streak: 0
    property string lastGuess: ""
    // Notas que soam em cada acorde da música: o nome que soa (com capo)
    // e a forma do app, sem capo.
    readonly property var templates: {
        var out = {}
        if (!song) return out
        var open = [4, 9, 2, 7, 11, 4]
        playSeq.forEach(function (p) {
            if (out[p.chord] !== undefined) return
            var sounding = Arara.CypherMusic.transposeChord(Examples.chordName(p.chord), shift + capo)
            var js = Arara.CypherMusic.chordShape(sounding, 0)
            if (!js) { out[p.chord] = null; return }
            var sh = JSON.parse(js), v = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            for (var st = 0; st < 6; ++st) if (sh.frets[st] >= 0) v[(open[st] + sh.frets[st]) % 12] = 1
            if (sh.frets[sh.root] >= 0) v[(open[sh.root] + sh.frets[sh.root]) % 12] = 1.3
            out[p.chord] = v
        })
        return out
    }
    function guessChord(chroma) {
        var best = "", bestScore = 0, cn = 0
        for (var i = 0; i < 12; ++i) cn += chroma[i] * chroma[i]
        if (cn <= 0) return ""
        for (var name in templates) {
            var v = templates[name]
            if (!v) continue
            var dot = 0, vn = 0
            for (var j = 0; j < 12; ++j) { dot += v[j] * chroma[j]; vn += v[j] * v[j] }
            var sc = dot / Math.sqrt(cn * vn)
            if (sc > bestScore) { bestScore = sc; best = name }
        }
        return bestScore > 0.72 ? best : ""
    }
    function goToSection() {
        if (!playSeq.length) return
        var item = secRepeater.itemAt(playSeq[playIdx].sec)
        if (!item) return
        var y = item.mapToItem(content, 0, 0).y + content.y - 70
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y))
    }
    function stepPlay(d) {
        var old = playSeq.length ? playSeq[playIdx].sec : -1
        playIdx = Math.max(0, Math.min(playSeq.length - 1, playIdx + d))
        if (playSeq.length && playSeq[playIdx].sec !== old) goToSection()
    }
    Connections {
        target: mic
        function onUpdated() {
            if (!page.playAlong) return
            var g = mic.level > 0.01 ? page.guessChord(mic.chroma) : ""
            page.streak = g !== "" && g === page.lastGuess ? page.streak + 1 : 1
            page.lastGuess = g
            if (page.streak < 3) return
            page.heard = g
            // Ouviu o próximo acorde (ou o seguinte, se pulou um): anda.
            var seq = page.playSeq, i = page.playIdx
            if (i + 1 < seq.length && seq[i + 1].chord === g) page.stepPlay(1)
            else if (i + 2 < seq.length && seq[i + 2].chord === g && seq[i + 1].chord !== seq[i].chord) page.stepPlay(2)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        HeaderBar {
            visible: !page.embedded
            Layout.fillWidth: true
            title: page.song ? page.song.title : ""
            AppButton {
                visible: !!page.libraryTrack
                text: "Estudar com a música"
                iconName: "play"
                suggested: true
                onClicked: Examples.studyRequested(page.libraryTrack, page.song)
            }
            AppButton {
                text: page.song && page.song.id ? "Editar" : "Editar uma cópia"
                flat: false
                onClicked: page.edit()
            }
            AppButton {
                text: page.playAlong ? "■ Tocar junto" : "Tocar junto"
                flat: false
                onClicked: page.playAlong = !page.playAlong
            }
            AppButton {
                text: page.scrolling ? "Parar" : "Rolar"
                flat: false
                onClicked: page.scrolling = !page.scrolling
            }
            AppButton { text: "Voltar"; flat: false; onClicked: page.back() }
        }

        // Barra do Tocar junto: acorde da vez, os próximos e o que o microfone ouve.
        Rectangle {
            visible: page.playAlong
            Layout.fillWidth: true
            implicitHeight: playRow.implicitHeight + 16
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.18 : 0.10)
            RowLayout {
                id: playRow
                x: 12; y: 8
                width: parent.width - 24
                spacing: 8
                AppButton { text: "◀"; flat: true; onClicked: page.stepPlay(-1) }
                Text {
                    text: page.playSeq.length ? page.song.sections[page.playSeq[page.playIdx].sec].name : "Sem acordes"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
                Repeater {
                    model: page.playSeq.slice(page.playIdx, page.playIdx + 5)
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: chipText.implicitWidth + 20; height: Theme.controlHeight; radius: Theme.radiusSmall
                        color: index === 0 ? Theme.chord : Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, 0.15)
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: page.t(Examples.chordName(parent.modelData.chord))
                            color: parent.index === 0 ? Theme.card : Theme.chord
                            font.family: Theme.monoFamily
                            font.pixelSize: parent.index === 0 ? Theme.fontSize + 3 : Theme.fontSize
                            font.bold: true
                        }
                    }
                }
                AppButton { text: "▶"; flat: true; onClicked: page.stepPlay(1) }
                Item { Layout.fillWidth: true }
                Text {
                    text: mic.error !== "" ? mic.error
                         : "Ouvindo: " + (page.heard ? page.t(Examples.chordName(page.heard)) : "…")
                    color: mic.error !== "" ? Theme.destructive : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
                Rectangle {
                    width: 60; height: 6; radius: 3
                    color: Theme.button
                    Rectangle { width: parent.width * Math.min(1, mic.level * 8); height: parent.height; radius: 3; color: Theme.accent }
                }
            }
        }

        Flickable {
            id: flick
            // Rolar com a mão para a rolagem automática.
            onMovementStarted: page.scrolling = false

            ScrollBar.vertical: AppScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: content.implicitHeight + 2 * Theme.pagePadding
            clip: true

            Column {
                id: content
                y: Theme.pagePadding
                width: Math.min(parent.width - 2 * Theme.pagePadding, 1400)
                x: (parent.width - width) / 2
                spacing: 14

                // ---- Cabeçalho, tom e como ver ----
                Card {
                    width: parent.width
                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Column {
                            Layout.fillWidth: true
                            spacing: 2
                            Row {
                                spacing: 8
                                Text {
                                    text: page.song ? page.t(page.song.key) : ""
                                    color: Theme.chord
                                    font.family: Theme.monoFamily
                                    font.pixelSize: 24
                                    font.weight: Font.Bold
                                }
                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: (page.capo ? "capo " + page.capo + "ª casa" : (page.songCapo ? "sem capo" : ""))
                                      + (page.tuning ? " · " + (page.tuning === 1 ? "½ tom abaixo" : "1 tom abaixo") : "")
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: page.song ? [page.song.artist, page.song.source].filter(function (s) { return !!s }).join(" · ") : ""
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                        AppButton { iconName: "remove"; onClicked: page.semitones-- }
                        Text {
                            Layout.preferredWidth: 32
                            horizontalAlignment: Text.AlignHCenter
                            text: (page.semitones > 0 ? "+" : "") + page.semitones
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        AppButton { iconName: "add"; onClicked: page.semitones++ }
                        AppButton {
                            visible: page.semitones !== 0
                            text: "Original"
                            flat: true
                            onClicked: page.semitones = 0
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        SegmentedControl {
                            model: [{ value: "all", label: "Tudo" },
                                    { value: "names", label: "Nomes" }]
                            // "Partitura" saiu (0.7.41): o "Tudo" já mostra a partitura.
                            current: page.viewMode
                            onActivated: (v) => page.viewMode = v
                        }
                        SegmentedControl {
                            model: [{ value: "0.8", label: "P" },
                                    { value: "1", label: "M" },
                                    { value: "1.4", label: "G" },
                                    { value: "1.8", label: "GG" }]
                            current: String(Theme.chordZoom)
                            onActivated: (v) => Theme.chordZoom = Number(v)
                        }
                        AppButton {
                            // Partitura das batidas: barras de ritmo ou notas.
                            visible: page.viewMode !== "names"
                            text: Theme.slashChords ? "Batida: barras" : "Batida: notas"
                            onClicked: Theme.slashChords = !Theme.slashChords
                        }
                        AppButton {
                            text: "Metrônomo"
                            onClicked: page.metroVisible = !page.metroVisible
                        }
                        AppButton {
                            visible: page.chordMode === "tab" || page.viewMode === "all" || (page.viewMode === "score" && !page.fullScore)
                            text: page.editingTab ? "Concluir edição" : (page.viewMode === "all" ? "Editar braços" : "Editar tab")
                            suggested: page.editingTab
                            onClicked: page.editingTab = !page.editingTab
                        }
                        AppButton {
                            visible: !!(page.song && page.song.video)
                            text: "Vídeo"
                            onClicked: Qt.openUrlExternally(page.song.video)
                        }
                        SegmentedControl {
                            visible: page.viewMode === "score"
                            model: [{ value: "chord", label: "Por acorde" },
                                    { value: "full", label: "Música inteira" }]
                            current: page.fullScore ? "full" : "chord"
                            onActivated: (v) => page.fullScore = (v === "full")
                        }
                    }
                }

                // ---- Opções (como o menu dos apps de cifra) ----
                Collapsible {
                    id: optionsGroup
                    width: parent.width
                    title: "Opções"
                    expanded: false
                    summary: [prefs.columns > 1 ? prefs.columns + " colunas" : "",
                              page.capo !== page.songCapo ? "capo " + page.capo : "",
                              page.tuning ? "afinação " + (page.tuning === 1 ? "½ tom abaixo" : "1 tom abaixo") : "",
                              !prefs.showTabs ? "sem tabs" : "", !prefs.showStrums ? "sem batidas" : "",
                              "rolagem " + prefs.scrollSpeed, page.songBpm + " BPM"]
                             .filter(function (x) { return x !== "" }).join(" · ")
                    Card {
                        width: parent.width
                        component Label: Text {
                            Layout.fillWidth: true
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            wrapMode: Text.WordWrap
                        }
                        component Hint: Text {
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        RowLayout {
                            width: parent.width
                            Label { text: "Rolagem automática" }
                            AppButton { iconName: "remove"; onClicked: prefs.scrollSpeed = Math.max(1, prefs.scrollSpeed - 1) }
                            Hint { text: "velocidade " + prefs.scrollSpeed; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignHCenter }
                            AppButton { iconName: "add"; onClicked: prefs.scrollSpeed = Math.min(7, prefs.scrollSpeed + 1) }
                            AppButton { text: page.scrolling ? "Parar" : "Rolar"; suggested: !page.scrolling; onClicked: page.scrolling = !page.scrolling }
                        }
                        RowLayout {
                            width: parent.width
                            Label { text: "Dividir em colunas" }
                            SegmentedControl {
                                model: [{ value: "1", label: "1" }, { value: "2", label: "2" }, { value: "3", label: "3" }]
                                current: String(prefs.columns)
                                onActivated: (v) => prefs.columns = Number(v)
                            }
                        }
                        RowLayout {
                            width: parent.width
                            Label { text: "Capotraste" + (page.capo !== page.songCapo ? " (as formas mudam, o som continua o mesmo)" : "") }
                            AppButton { iconName: "remove"; onClicked: page.capo = Math.max(0, page.capo - 1) }
                            Hint { text: page.capo ? page.capo + "ª casa" : "sem capo"; Layout.preferredWidth: 80; horizontalAlignment: Text.AlignHCenter }
                            AppButton { iconName: "add"; onClicked: page.capo = Math.min(11, page.capo + 1) }
                        }
                        RowLayout {
                            width: parent.width
                            Label { text: "Afinação" }
                            SegmentedControl {
                                model: [{ value: "0", label: "Padrão" }, { value: "1", label: "½ tom abaixo" }, { value: "2", label: "1 tom abaixo" }]
                                current: String(page.tuning)
                                onActivated: (v) => page.tuning = Number(v)
                            }
                        }
                        RowLayout {
                            width: parent.width
                            Label { text: "Tablaturas" }
                            SegmentedControl {
                                model: [{ value: "1", label: "Mostrar" }, { value: "0", label: "Esconder" }]
                                current: prefs.showTabs ? "1" : "0"
                                onActivated: (v) => prefs.showTabs = (v === "1")
                            }
                        }
                        RowLayout {
                            width: parent.width
                            Label { text: "Batidas" }
                            SegmentedControl {
                                model: [{ value: "1", label: "Mostrar" }, { value: "0", label: "Esconder" }]
                                current: prefs.showStrums ? "1" : "0"
                                onActivated: (v) => prefs.showStrums = (v === "1")
                            }
                        }
                        RowLayout {
                            width: parent.width
                            Label { text: "Metrônomo (" + page.songBpm + " BPM" + (page.song && (page.song.bpm || page.songBpm !== 80) ? ", da música)" : ", padrão)") }
                            AppButton { text: page.metroVisible ? "Esconder" : "Mostrar"; onClicked: page.metroVisible = !page.metroVisible }
                        }
                        RowLayout {
                            width: parent.width
                            Label { text: "Pedal passador (Page Down / Page Up ou setas)" }
                            SegmentedControl {
                                model: [{ value: "1", label: "Ligado" }, { value: "0", label: "Desligado" }]
                                current: prefs.pedal ? "1" : "0"
                                onActivated: (v) => prefs.pedal = (v === "1")
                            }
                        }
                        Hint {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Afinador e Tocar junto usam o microfone e chegam no próximo passo."
                        }
                        AppButton {
                            text: "Restaurar padrões"
                            onClicked: page.restoreDefaults()
                        }
                    }
                }

                // ---- Batidas (fechadas: só as setas) ----
                // Escondida no Arara Music: cada parte já mostra a batida na tab
                // (pedido do HP na 0.7.41). A batida se edita no editor.
                Collapsible {
                    id: strumsGroup
                    visible: false
                    width: parent.width
                    title: page.usedStrums.length > 1 ? "Batidas" : "Batida"
                    expanded: false
                    summary: page.rev, page.usedStrums.map(function (s) { return page.arrows(s.pattern) }).join("   |   ")

                    Repeater {
                        model: page.usedStrums
                        Column {
                            id: strumBlock
                            required property var modelData
                            width: strumsGroup.width
                            spacing: 6
                            Text { visible: page.usedStrums.length > 1; text: strumBlock.modelData.name; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1 }
                            Card {
                                width: parent.width
                                Row {
                                    spacing: 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Repeater {
                                        model: strumBlock.modelData.pattern
                                        Column {
                                            id: beat
                                            required property string modelData
                                            required property int index
                                            width: 44
                                            spacing: 2
                                            Text {
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Examples.strokeArrow(beat.modelData)
                                                color: beat.modelData === "" ? Theme.textDim
                                                     : Examples.isMute(beat.modelData) ? Theme.textDim : Theme.accent
                                                font.pixelSize: 26
                                                font.weight: Font.Bold
                                            }
                                            Text {
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: (beat.modelData ? Examples.strokeLabel(beat.modelData) : " ")
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                            }
                                            Text {
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: strumBlock.modelData.counts[beat.index] || ""
                                                color: Theme.textDim
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize - 2
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                }

                // ---- Partitura da música inteira ----
                Card {
                    id: fullScoreCard
                    visible: page.showFullScore
                    width: parent.width
                    padding: 10
                    readonly property int perRow: Math.max(1, Math.floor((width - 20 - 48 * page.zoom) / (190 * page.zoom)))
                    Repeater {
                        model: page.showFullScore ? page.scoreBlocks : []
                        Column {
                            id: block
                            required property var modelData
                            width: fullScoreCard.width - 20
                            Repeater {
                                model: block.modelData.tab ? 0 : Math.ceil(block.modelData.measures.length / fullScoreCard.perRow)
                                ScoreRow {
                                    required property int index
                                    width: block.width
                                    height: implicitHeight
                                    measures: block.modelData.measures.slice(index * fullScoreCard.perRow,
                                                                             (index + 1) * fullScoreCard.perRow)
                                    pattern: ["D"]
                                    slots: fullScoreCard.perRow
                                    semitones: page.shift
                                    zoom: page.zoom
                                }
                            }
                            TabScore {
                                visible: !!block.modelData.tab
                                width: block.width
                                height: implicitHeight
                                tab: block.modelData.tab || ""
                                label: block.modelData.label || ""
                                startNumber: block.modelData.start || 0
                                keyName: page.song ? page.t(page.song.key) : "C"
                                zoom: page.zoom
                            }
                        }
                    }
                }


                // ---- Seções ----
                RowLayout {
                    visible: !page.showFullScore && !!page.song && page.song.sections.length > 1
                    width: parent.width
                    Text {
                        Layout.fillWidth: true
                        text: "Partes"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    AppButton { text: "Abrir todas"; flat: true; onClicked: page.setAll(true) }
                    AppButton { text: "Fechar todas"; flat: true; onClicked: page.setAll(false) }
                }
                Grid {
                    id: secGrid
                    width: content.width
                    columns: Math.max(1, Math.min(prefs.columns, Math.floor(content.width / 330)))
                    columnSpacing: 16
                    rowSpacing: 14
                    Repeater {
                        id: secRepeater
                        model: page.song && !page.showFullScore ? page.song.sections : []
                        Collapsible {
                            id: section
                            required property var modelData
                            required property int index
                            readonly property var strum: Examples.strumOf(page.song, modelData)
                            readonly property string sameAs: page.sameAs(index)
                            readonly property var chords: page.rev, page.partChords(page.song.sections[index])
                            width: (secGrid.width - (secGrid.columns - 1) * secGrid.columnSpacing) / secGrid.columns
                            title: modelData.name
                            badge: modelData.repeat > 1 ? modelData.repeat + "×" : ""
                            summary: (sameAs ? "igual a " + sameAs + " · " : "") + page.chordList(modelData)
                            expanded: sameAs === ""
                            active: page.embedded && index === page.activeSection
                            concealed: active && page.concealActive
                            Connections {
                                target: page
                                function onSetAll(open) { section.expanded = open }
                            }

                            Card {
                                width: parent.width
                                // Nomes: só a tab, no padrão novo (cores, anel no 0, nome do
                                // acorde marcado em cima do toque), sem a pauta.
                                TabScore {
                                    visible: prefs.showTabs && !!section.modelData.tab && ["tab", "score", "lesson", "all"].indexOf(page.viewMode) < 0
                                    width: parent.width
                                    height: implicitHeight
                                    tab: page.rev, visible ? page.song.sections[section.index].tab : ""
                                    showStaff: false
                                    showChords: true
                                    semitones: page.shift
                                    keyName: page.song ? page.t(page.song.key) : "C"
                                    zoom: page.zoom
                                }
                                LessonTab {
                                    visible: prefs.showTabs && !!section.modelData.tab && page.viewMode === "lesson"
                                    width: parent.width
                                    height: implicitHeight
                                    tab: visible ? section.modelData.tab : ""
                                    song: page.song
                                    semitones: page.shift
                                    capo: page.capo
                                    bpm: section.strum && section.strum.bpm ? section.strum.bpm : page.songBpm
                                    zoom: page.zoom
                                    onBeat: (strong) => metroSound.play(strong)
                                }
                                TabScore {
                                    visible: prefs.showTabs && !!section.modelData.tab && (page.viewMode === "tab" || page.viewMode === "score")
                                    width: parent.width
                                    height: implicitHeight
                                    tab: page.rev, visible ? page.song.sections[section.index].tab : ""
                                    showChords: true
                                    semitones: page.shift
                                    keyName: page.song ? page.t(page.song.key) : "C"
                                    zoom: page.zoom
                                    editing: page.editingTab
                                    onArrowClicked: (sys, ev, arrow) => {
                                        // modelData é uma cópia: muda a parte de verdade na música.
                                        var sec = page.song.sections[section.index]
                                        sec.tab = Arara.CypherMusic.setArrow(sec.tab, sys, ev, arrow)
                                        page.persist()
                                    }
                                }
                                // Tab: os acordes numa tab só, comprida, como na partitura
                                // (com "Editar tab", toca numa casa ou numa seta para mudar).
                                // Tudo: braço + partitura + tab de cada acorde, num quadro só
                                // (editando, mostra a tab inteira para mexer).
                                SectionView {
                                    visible: page.viewMode === "all"
                                    editing: page.editingTab
                                    onEdited: page.persist()
                                    width: parent.width
                                    section: visible ? page.song.sections[section.index] : null
                                    song: page.song
                                    strum: section.strum
                                    semitones: page.shift
                                    zoom: page.zoom
                                    keyName: page.song ? page.t(page.song.key) : "C"
                                    rev: page.rev
                                }
                                ChordTab {
                                    visible: page.chordMode === "tab" && section.modelData.chords.length > 0
                                    width: parent.width
                                    chords: visible ? section.modelData.chords : []
                                    song: page.song
                                    strum: section.strum
                                    section: page.song.sections[section.index]
                                    semitones: page.shift
                                    zoom: page.zoom
                                    rev: page.rev
                                    editing: page.editingTab
                                    status: page.editStatus
                                    onEdited: page.persist()
                                }
                                Flow {
                                    visible: page.chordMode !== "tab" && page.viewMode !== "all" && section.chords.length > 0
                                    width: parent.width
                                    spacing: 8
                                    Repeater {
                                        model: section.chords
                                        Rectangle {
                                            id: chordBox
                                            required property string modelData
                                            readonly property string chordName: Examples.chordName(modelData)
                                            readonly property var voicing: Examples.voicing(page.song, modelData)
                                            readonly property real zm: page.zoom
                                            readonly property bool diag: page.chordMode === "diagram" && diagram.visible
                                            readonly property bool tab: page.chordMode === "tab" && strumTab.visible
                                            readonly property bool big: page.chordMode === "big" && bigDiagram.visible
                                            readonly property bool score: page.chordMode === "score" && notation.visible
                                            readonly property real contentW: diag ? diagram.implicitWidth * zm : tab ? strumTab.implicitWidth * zm
                                                                           : big ? bigDiagram.implicitWidth * zm
                                                                           : score ? notation.implicitWidth : 0
                                            readonly property real contentH: diag ? diagram.implicitHeight * zm : tab ? strumTab.implicitHeight * zm
                                                                           : big ? bigDiagram.implicitHeight * zm
                                                                           : score ? notation.implicitHeight : 0
                                            width: Math.max(64 * zm, contentW + 16, chordText.implicitWidth + 24)
                                            height: contentH > 0 ? chordText.implicitHeight + contentH + 24 : chordText.implicitHeight + 20
                                            radius: Theme.radiusSmall
                                            color: Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, Theme.dark ? 0.16 : 0.09)
                                            Text {
                                                id: chordText
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: chordBox.contentH > 0 ? 8 : (parent.height - height) / 2
                                                text: page.t(chordBox.chordName)
                                                color: Theme.chord
                                                font.family: Theme.monoFamily
                                                font.pixelSize: (Theme.fontSize + 4) * chordBox.zm
                                                font.weight: Font.Bold
                                            }
                                            ChordDiagram {
                                                id: diagram
                                                scale: chordBox.zm
                                                transformOrigin: Item.Top
                                                visible: page.chordMode === "diagram" && shape !== null
                                                chord: chordBox.chordName
                                                voicing: chordBox.voicing
                                                semitones: page.shift
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.horizontalCenterOffset: -4
                                                anchors.top: chordText.bottom
                                                anchors.topMargin: 6
                                            }
                                            BigChordDiagram {
                                                id: bigDiagram
                                                scale: chordBox.zm
                                                transformOrigin: Item.Top
                                                visible: page.chordMode === "big" && shape !== null
                                                chord: chordBox.chordName
                                                voicing: chordBox.voicing
                                                semitones: page.shift
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.horizontalCenterOffset: -8
                                                anchors.top: chordText.bottom
                                                anchors.topMargin: 8
                                            }
                                            NotationView {
                                                id: notation
                                                zoom: chordBox.zm
                                                visible: page.chordMode === "score" && shape !== null
                                                width: implicitWidth
                                                height: implicitHeight
                                                chord: chordBox.chordName
                                                voicing: chordBox.voicing
                                                semitones: page.shift
                                                pattern: section.strum ? section.strum.pattern : ["D"]
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.top: chordText.bottom
                                                anchors.topMargin: 4
                                            }
                                            StrumTab {
                                                id: strumTab
                                                scale: chordBox.zm
                                                transformOrigin: Item.Top
                                                visible: page.chordMode === "tab" && shape !== null
                                                chord: chordBox.chordName
                                                voicing: chordBox.voicing
                                                semitones: page.shift
                                                pattern: section.strum ? section.strum.pattern : ["D"]
                                                counts: section.strum ? section.strum.counts : []
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.top: chordText.bottom
                                                anchors.topMargin: 6
                                            }
                                        }
                                    }
                                }
                                Text {
                                    visible: !!section.modelData.note
                                    text: section.modelData.note || ""
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    font.italic: true
                                }
                            }
                        }
                    }
                }

                // ---- Letra ----
                Collapsible {
                    visible: !page.embedded
                    width: parent.width
                    title: "Letra"
                    expanded: false
                    summary: page.lyrics ? (page.lyrics.synced.length ? "sincronizada · " : "") + page.lyrics.plain.split("\n")[0]
                                         : "buscar no LRCLIB"
                    Card {
                        width: parent.width
                        Row {
                            spacing: 8
                            AppButton {
                                visible: !page.lyrics
                                text: "Buscar letra no LRCLIB"
                                suggested: true
                                onClicked: page.fetchLyrics()
                            }
                            AppButton {
                                visible: !!page.lyrics && page.lyrics.synced.length > 0
                                text: page.lyricsPlaying ? "Pausar" : (page.lyricsNow > 0 ? "Continuar" : "Acompanhar")
                                suggested: !page.lyricsPlaying
                                onClicked: page.toggleLyrics()
                            }
                            AppButton {
                                visible: !!page.lyrics && page.lyrics.synced.length > 0 && page.lyricsNow > 0
                                text: "Do começo"
                                flat: true
                                onClicked: { page.lyricsNow = 0; page.lyricsLine = -1; page.lyricsT0 = Date.now() }
                            }
                            AppButton {
                                visible: !!page.lyrics
                                text: "Buscar de novo"
                                flat: true
                                onClicked: page.fetchLyrics()
                            }
                        }
                        Text {
                            visible: page.lyricsStatus.length > 0
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: page.lyricsStatus
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        // Sincronizada: linha da vez em destaque.
                        Column {
                            visible: !!page.lyrics && page.lyrics.synced.length > 0
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: page.lyrics ? page.lyrics.synced : []
                                Text {
                                    required property var modelData
                                    required property int index
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: modelData.text || "♪"
                                    color: index === page.lyricsLine ? Theme.chord : (index < page.lyricsLine ? Theme.textDim : Theme.text)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: (Theme.fontSize + (index === page.lyricsLine ? 4 : 1)) * page.zoom
                                    font.weight: index === page.lyricsLine ? Font.Bold : Font.Normal
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: { page.lyricsNow = parent.modelData.t; page.lyricsLine = parent.index; page.lyricsT0 = Date.now() - parent.modelData.t * 1000 }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: !!page.lyrics && page.lyrics.synced.length === 0
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: page.lyrics ? page.lyrics.plain : ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: (Theme.fontSize + 1) * page.zoom
                            lineHeight: 1.3
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Letras de lrclib.net. Ficam só no seu computador."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }

                Text {
                    visible: !page.embedded && !!page.song && !page.song.id && !page.lyrics
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "A letra não vem com o app. Abra Letra acima para baixar do LRCLIB."
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    // Metrônomo flutuante, no canto, sem tapar a cifra.
    Rectangle {
        visible: page.metroVisible
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        width: Math.max(metroRow.implicitWidth, metroSound.implicitWidth) + 24
        height: metroRow.implicitHeight + metroSound.implicitHeight + 28
        radius: Theme.radius
        color: Theme.card
        border.width: 1
        border.color: Theme.border
        MetroSound {
            id: metroSound
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
        }
        RowLayout {
            id: metroRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 10
            spacing: 8
            Row {
                spacing: 5
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        width: 12; height: 12; radius: 6
                        color: metro.running && ((metro.beat % 4) + 4) % 4 === index
                               ? (index === 0 ? Theme.chord : Theme.accent) : Theme.button
                    }
                }
            }
            AppButton { iconName: "remove"; onClicked: { metro.bpm = Math.max(30, metro.bpm - 2); metro.t0 = Date.now(); metro.beat = -1 } }
            Text {
                text: metro.bpm + " BPM"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.weight: Font.Bold
            }
            AppButton { iconName: "add"; onClicked: { metro.bpm = Math.min(240, metro.bpm + 2); metro.t0 = Date.now(); metro.beat = -1 } }
            AppButton { text: metro.running ? "Parar" : "Tocar"; suggested: !metro.running; onClicked: page.toggleMetro() }
            AppButton {
                visible: metro.bpm !== page.songBpm
                text: "BPM da música"
                flat: true
                onClicked: { metro.bpm = page.songBpm; metro.t0 = Date.now(); metro.beat = -1 }
            }
        }
    }
}
