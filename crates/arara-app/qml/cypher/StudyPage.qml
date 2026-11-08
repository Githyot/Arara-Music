import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtMultimedia
import Qt.labs.settings
import AraraCypher
import io.github.arara as Arara

// Modo estudo: escolhe uma música (e uma parte) e treina de três jeitos:
// - Troca de acordes: metrônomo marcando quando trocar, com o próximo acorde à vista.
// - Que acorde é esse?: quiz de formas e nomes dos acordes da música.
// - Batida no tempo: tocar (Espaço ou o botão) junto com a batida e ganhar pontos.
// Guarda dias seguidos de estudo, minutos, estrelas e recordes por música.
Rectangle {
    id: page
    color: Theme.window

    property string mode: "home"        // "home" | "practice" | "quiz" | "rhythm"
    property var song: null
    property int sectionIndex: -1       // -1 = música inteira
    property int stats_rev: 0

    // ---- Progresso guardado ----
    Settings {
        id: store
        category: "estudo"
        property string stats: "{}"
    }
    readonly property var stats: { stats_rev; try { return JSON.parse(store.stats) } catch (e) { return {} } }
    function saveStats(s) { store.stats = JSON.stringify(s); stats_rev++ }

    function today() {
        var d = new Date()
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }
    function dayBefore(day) {
        var p = day.split("-")
        var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]) - 1)
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }
    readonly property int streak: {
        var s = stats
        if (!s.lastDay) return 0
        var t = today()
        return (s.lastDay === t || s.lastDay === dayBefore(t)) ? (s.streak || 0) : 0
    }
    readonly property int minutesToday: stats.day === today() ? Math.floor((stats.daySec || 0) / 60) : 0
    readonly property int totalMinutes: Math.floor((stats.totalSec || 0) / 60)

    // Conta um estudo de hoje (mantém a sequência de dias) e soma tempo e estrelas.
    function record(seconds, stars) {
        var s = JSON.parse(JSON.stringify(stats))
        var t = today()
        if (s.lastDay !== t) {
            s.streak = s.lastDay === dayBefore(t) ? (s.streak || 0) + 1 : 1
            s.lastDay = t
        }
        if (s.day !== t) { s.day = t; s.daySec = 0 }
        s.daySec = (s.daySec || 0) + seconds
        s.totalSec = (s.totalSec || 0) + seconds
        s.stars = (s.stars || 0) + stars
        saveStats(s)
    }
    function songKey() { return song ? (song.id || song.title) : "" }
    function best(kind) {
        var b = stats.best && stats.best[songKey()]
        return b && b[kind] ? b[kind] : 0
    }
    // Guarda o recorde; devolve verdadeiro se bateu o anterior.
    function setBest(kind, value) {
        var s = JSON.parse(JSON.stringify(stats))
        if (!s.best) s.best = {}
        var k = songKey()
        if (!s.best[k]) s.best[k] = {}
        var beat = value > (s.best[k][kind] || 0)
        if (beat) s.best[k][kind] = value
        saveStats(s)
        return beat
    }
    function starsFor(score) { return score >= 90 ? 3 : score >= 70 ? 2 : score >= 50 ? 1 : 0 }
    function starText(n) { return "★★★".slice(0, n) + "☆☆☆".slice(0, 3 - n) }

    // ---- Músicas ----
    readonly property var allSongs: {
        Arara.CypherLibrary.revision
        var mine = []
        try { mine = JSON.parse(Arara.CypherLibrary.songs()) } catch (e) {}
        return mine.concat(Examples.visibleSongs)
    }
    // Acordes para treinar, em ordem (da parte escolhida ou da música inteira).
    readonly property var sequence: {
        if (!song) return []
        var out = []
        for (var i = 0; i < song.sections.length; ++i)
            if (sectionIndex < 0 || sectionIndex === i)
                out = out.concat(song.sections[i].chords)
        return out
    }
    // Acordes diferentes (pelo nome), com a forma da aula quando houver.
    readonly property var distinct: {
        var seen = {}, out = []
        for (var i = 0; i < sequence.length; ++i) {
            var n = Examples.chordName(sequence[i])
            if (!seen[n]) { seen[n] = true; out.push(sequence[i]) }
        }
        return out
    }
    readonly property var strums: {
        if (!song || !song.strums || !song.strums.length) return [{ name: "Batida", pattern: ["D", "", "D", "U", "", "U", "D", "U"],
                                              counts: ["1", "e", "2", "e", "3", "e", "4", "e"] }]
        return song.strums
    }

    // ---- Metrônomo ----
    property int bpm: 70
    property bool sound: true
    MetroSound { id: metroSound; visible: false }
    function tic(strong) { if (sound) metroSound.play(strong) }

    // Relógio comum aos jogos: um Timer rápido que olha a hora de verdade,
    // para o tempo não atrasar com o passar dos compassos.
    property real t0: 0
    property bool running: false
    property int tick: -999             // colcheia atual (negativa na contagem)
    property real startedAt: 0
    signal tickChanged2(int n)
    Timer {
        interval: 5
        repeat: true
        running: page.running
        onTriggered: {
            var n = Math.floor((Date.now() - page.t0) / page.slotMs)
            if (n !== page.tick) { page.tick = n; page.tickChanged2(n) }
        }
    }
    readonly property real slotMs: 30000 / bpm   // colcheia
    function startClock(countInSlots) {
        t0 = Date.now() + countInSlots * slotMs
        tick = -countInSlots - 1
        startedAt = Date.now()
        running = true
        keyCatcher.forceActiveFocus()
    }
    function stopClock() {
        if (running) {
            var sec = Math.round((Date.now() - startedAt) / 1000)
            if (sec >= 5) record(sec, 0)
        }
        running = false
    }
    function leave() { stopClock(); mode = "home" }

    // ---- Troca de acordes ----
    property int beatsPerChord: 4
    property bool speedUp: false
    property int laps: 0
    property int lapStars: 0
    readonly property int beat: Math.floor(tick / 2)         // semínima
    readonly property int chordIdx: beat < 0 || sequence.length === 0 ? 0 : Math.floor(beat / beatsPerChord) % sequence.length

    // ---- Quiz ----
    property var questions: []
    property int qIndex: 0
    property int qRight: 0
    property int qCombo: 0
    property string picked: ""
    property real quizStart: 0
    readonly property var commonChords: ["C", "G", "D", "A", "E", "Am", "Em", "Dm", "F", "Bm", "B7", "E7"]
    function shuffle(a) {
        a = a.slice()
        for (var i = a.length - 1; i > 0; --i) {
            var j = Math.floor(Math.random() * (i + 1)); var t = a[i]; a[i] = a[j]; a[j] = t
        }
        return a
    }
    function startQuiz() {
        var pool = distinct.slice()
        var names = pool.map(function (c) { return Examples.chordName(c) })
        var extra = shuffle(commonChords).filter(function (c) { return names.indexOf(c) < 0 })
        var qs = []
        for (var i = 0; i < 10; ++i) {
            var token = pool[i % pool.length]
            if (i % pool.length === 0) pool = shuffle(pool)
            token = pool[i % pool.length]
            var others = shuffle(pool.filter(function (t) { return Examples.chordName(t) !== Examples.chordName(token) }))
                         .concat(extra).slice(0, 3)
            qs.push({ token: token, type: i % 2 === 0 ? "name" : "shape", options: shuffle([token].concat(others)) })
        }
        questions = qs
        qIndex = 0; qRight = 0; qCombo = 0; picked = ""
        quizStart = Date.now()
        mode = "quiz"
    }
    function answer(token) {
        if (picked !== "") return
        picked = token
        var ok = Examples.chordName(token) === Examples.chordName(questions[qIndex].token)
        if (ok) { qRight++; qCombo++ } else qCombo = 0
        nextQuestion.restart()
    }
    Timer {
        id: nextQuestion
        interval: 900
        onTriggered: {
            page.picked = ""
            page.qIndex++
            if (page.qIndex >= page.questions.length) {
                var score = page.qRight * 10
                page.quizRecord = page.setBest("quiz", score)
                page.record(Math.round((Date.now() - page.quizStart) / 1000), page.starsFor(score))
            }
        }
    }
    property bool quizRecord: false

    // ---- Batida no tempo ----
    property int strumIndex: 0
    readonly property var pattern: strums[Math.min(strumIndex, strums.length - 1)].pattern
    readonly property int measures: 4
    property var taps: []
    property var rhythmResult: null
    property bool rhythmRecord: false
    property string flash: ""
    readonly property var expected: {
        var out = []
        for (var m = 0; m < measures; ++m)
            for (var k = 0; k < pattern.length; ++k)
                if (pattern[k] !== "") out.push((m * pattern.length + k) * slotMs)
        return out
    }
    function startRhythm() {
        taps = []
        rhythmResult = null
        flash = ""
        startClock(pattern.length)       // um compasso de contagem
    }
    function tap() {
        if (mode !== "rhythm" || !running || tick < -2) return
        var t = Date.now() - t0
        var list = taps.slice(); list.push(t); taps = list
        var near = 1e9
        for (var i = 0; i < expected.length; ++i) near = Math.min(near, Math.abs(expected[i] - t))
        flash = near <= 60 ? "Perfeito!" : near <= 130 ? "Bom" : "Fora do tempo"
        flashTimer.restart()
    }
    Timer { id: flashTimer; interval: 450; onTriggered: page.flash = "" }

    onTickChanged2: (n) => {
        if (mode === "practice") {
            if (n % 2 !== 0) return
            var b = Math.floor(n / 2)
            tic(b < 0 ? b === -4 : b % beatsPerChord === 0)
            // Fim de uma volta pela sequência.
            var lapBeats = beatsPerChord * sequence.length
            if (b > 0 && b % lapBeats === 0) {
                laps++
                if (lapStars < 3) lapStars++
                setBest("bpm", bpm)
                if (speedUp) {
                    // Recomeça a contagem no novo andamento, sem pausa.
                    bpm = Math.min(200, bpm + 5)
                    t0 = Date.now() - 0
                    tick = 0
                }
            }
        } else if (mode === "rhythm") {
            var len = pattern.length
            if (n % 2 === 0) tic(n < 0 ? n === -len : (n % len) === 0)
            if (n >= measures * len + 2) {
                running = false
                var r = JSON.parse(Arara.CypherMusic.judgeRhythm(JSON.stringify(expected), JSON.stringify(taps)))
                rhythmResult = r
                rhythmRecord = setBest("rhythm", r.score)
                record(Math.round((Date.now() - startedAt) / 1000), starsFor(r.score))
            }
        }
    }

    // Teclado: Espaço toca no jogo de batida, Esc volta.
    Item {
        id: keyCatcher
        focus: true
        Keys.onSpacePressed: (e) => { if (!e.isAutoRepeat) page.tap(); e.accepted = true }
        Keys.onEscapePressed: page.leave()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        HeaderBar {
            Layout.fillWidth: true
            title: page.mode === "home" ? "Estudo"
                 : page.mode === "practice" ? "Troca de acordes"
                 : page.mode === "quiz" ? "Que acorde é esse?" : "Batida no tempo"
            AppButton {
                visible: page.mode !== "home"
                text: "Voltar"
                flat: true
                onClicked: page.leave()
            }
        }

        Flickable {
            id: flick
            ScrollBar.vertical: AppScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight + 2 * Theme.pagePadding
            clip: true

            Column {
                id: col
                y: Theme.pagePadding
                width: Math.min(parent.width - 2 * Theme.pagePadding, 720)
                x: (parent.width - width) / 2
                spacing: 14

                // ================= Início =================
                Card {
                    visible: page.mode === "home"
                    width: parent.width
                    RowLayout {
                        width: parent.width
                        spacing: 12
                        Repeater {
                            model: [
                                { big: page.streak > 0 ? "🔥 " + page.streak : "0", small: page.streak === 1 ? "dia seguido" : "dias seguidos" },
                                { big: page.minutesToday + " min", small: "hoje (" + page.totalMinutes + " no total)" },
                                { big: "★ " + (page.stats.stars || 0), small: "estrelas" }
                            ]
                            Column {
                                required property var modelData
                                Layout.fillWidth: true
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.big
                                    color: Theme.chord
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 24
                                    font.weight: Font.Bold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.small
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }
                        }
                    }
                }

                Collapsible {
                    id: songPick
                    visible: page.mode === "home"
                    width: parent.width
                    title: "Música"
                    expanded: !page.song
                    summary: page.song ? page.song.title + (page.sectionIndex >= 0 ? " · " + page.song.sections[page.sectionIndex].name : " · inteira") : "escolha uma"
                    Flow {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: page.allSongs
                            AppButton {
                                required property var modelData
                                text: modelData.title
                                suggested: page.song === modelData
                                onClicked: { page.song = modelData; page.sectionIndex = -1; page.strumIndex = 0 }
                            }
                        }
                    }
                }

                Card {
                    visible: page.mode === "home" && !!page.song
                    width: parent.width
                    Text {
                        text: "Treinar"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        AppButton {
                            text: "Música inteira"
                            suggested: page.sectionIndex === -1
                            onClicked: page.sectionIndex = -1
                        }
                        Repeater {
                            model: page.song ? page.song.sections : []
                            AppButton {
                                required property var modelData
                                required property int index
                                visible: modelData.chords.length > 0
                                text: modelData.name
                                suggested: page.sectionIndex === index
                                onClicked: page.sectionIndex = index
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: page.sequence.map(function (c) { return Examples.chordName(c) }).join("  ")
                        color: Theme.chord
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSize
                    }
                }

                // Os três jogos.
                Repeater {
                    model: page.mode === "home" && page.song ? [
                        { id: "practice", title: "Troca de acordes", text: "O metrônomo marca quando trocar e o próximo acorde fica à vista. Ligue \"Acelerar\" para subir 5 BPM a cada volta.", best: page.best("bpm") ? "Recorde: " + page.best("bpm") + " BPM" : "" },
                        { id: "quiz", title: "Que acorde é esse?", text: "10 perguntas com os acordes desta música: ache o nome pelo desenho, ou o desenho pelo nome.", best: page.best("quiz") ? "Recorde: " + page.best("quiz") + "%" : "" },
                        { id: "rhythm", title: "Batida no tempo", text: "Toque Espaço (ou o botão grande) em cada palhetada da batida, junto com o metrônomo. 4 compassos por rodada.", best: page.best("rhythm") ? "Recorde: " + page.best("rhythm") + "%" : "" }
                    ] : []
                    Card {
                        required property var modelData
                        width: col.width
                        RowLayout {
                            width: parent.width
                            spacing: 12
                            Column {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: modelData.title
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize + 2
                                    font.weight: Font.Bold
                                }
                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: modelData.text
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }
                                Text {
                                    visible: modelData.best !== ""
                                    text: modelData.best
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    font.weight: Font.Bold
                                }
                            }
                            AppButton {
                                text: "Começar"
                                suggested: true
                                enabled: page.sequence.length > 0
                                onClicked: {
                                    if (modelData.id === "quiz") { page.startQuiz(); return }
                                    page.laps = 0; page.lapStars = 0; page.rhythmResult = null
                                    // Começa no recorde, ou no BPM da música (quando a cifra diz).
                                    var songBpm = page.song.bpm || 0
                                    if (!songBpm && page.song.strums)
                                        for (var i = 0; i < page.song.strums.length; ++i) songBpm = songBpm || page.song.strums[i].bpm || 0
                                    page.bpm = modelData.id === "practice"
                                            ? (page.best("bpm") || songBpm || 60)
                                            : (songBpm || 70)
                                    // Foco antes de trocar de tela: este botão some com a troca.
                                    keyCatcher.forceActiveFocus()
                                    page.mode = modelData.id
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: page.mode === "home" && !page.song
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: "Escolha uma música para começar. Dá para treinar a música inteira ou só uma parte."
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                // ================= Andamento (troca e batida) =================
                Card {
                    visible: page.mode === "practice" || page.mode === "rhythm"
                    width: parent.width
                    RowLayout {
                        width: parent.width
                        spacing: 8
                        Text {
                            text: page.bpm + " BPM"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 4
                            font.weight: Font.Bold
                            Layout.preferredWidth: 100
                        }
                        AppButton { iconName: "remove"; enabled: !page.running; onClicked: page.bpm = Math.max(30, page.bpm - 5) }
                        Slider {
                            Layout.fillWidth: true
                            from: 30; to: 200; stepSize: 1
                            value: page.bpm
                            enabled: !page.running
                            onMoved: page.bpm = value
                        }
                        AppButton { iconName: "add"; enabled: !page.running; onClicked: page.bpm = Math.min(200, page.bpm + 5) }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        SegmentedControl {
                            visible: page.mode === "practice"
                            model: [{ value: "2", label: "2 tempos" }, { value: "4", label: "4 tempos" }, { value: "8", label: "8 tempos" }]
                            current: String(page.beatsPerChord)
                            onActivated: (v) => { if (!page.running) page.beatsPerChord = Number(v) }
                        }
                        SegmentedControl {
                            visible: page.mode === "rhythm" && page.strums.length > 1
                            model: page.strums.map(function (s, i) { return { value: String(i), label: "Batida " + (i + 1) } })
                            current: String(page.strumIndex)
                            onActivated: (v) => { if (!page.running) { page.strumIndex = Number(v); page.rhythmResult = null } }
                        }
                        AppButton {
                            visible: page.mode === "practice"
                            text: page.speedUp ? "Acelerar: sim" : "Acelerar: não"
                            onClicked: page.speedUp = !page.speedUp
                        }
                        AppButton {
                            text: page.sound ? "Som: ligado" : "Som: desligado"
                            onClicked: page.sound = !page.sound
                        }
                    }
                }

                // ================= Troca de acordes =================
                Card {
                    visible: page.mode === "practice"
                    width: parent.width
                    // Tempos do compasso.
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        Repeater {
                            model: page.beatsPerChord
                            Rectangle {
                                required property int index
                                readonly property bool on: page.running && page.beat >= 0 && page.beat % page.beatsPerChord === index
                                width: 18; height: 18; radius: 9
                                color: on ? (index === 0 ? Theme.chord : Theme.accent) : Theme.button
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: page.running && page.beat < 0
                        text: String(-page.beat)
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 56
                        font.weight: Font.Bold
                    }
                    RowLayout {
                        width: parent.width
                        visible: !page.running || page.beat >= 0
                        Column {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: page.sequence.length ? Examples.chordName(page.sequence[page.chordIdx]) : ""
                                color: Theme.chord
                                font.family: Theme.monoFamily
                                font.pixelSize: 40
                                font.weight: Font.Bold
                            }
                            BigChordDiagram {
                                anchors.horizontalCenter: parent.horizontalCenter
                                chord: page.sequence.length ? Examples.chordName(page.sequence[page.chordIdx]) : "C"
                                voicing: page.sequence.length ? Examples.voicing(page.song, page.sequence[page.chordIdx]) : null
                            }
                        }
                        Column {
                            Layout.preferredWidth: 150
                            spacing: 4
                            opacity: 0.75
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Próximo"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                readonly property string tok: page.sequence.length ? page.sequence[(page.chordIdx + 1) % page.sequence.length] : ""
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Examples.chordName(tok)
                                color: Theme.chord
                                font.family: Theme.monoFamily
                                font.pixelSize: 24
                                font.weight: Font.Bold
                            }
                            ChordDiagram {
                                anchors.horizontalCenter: parent.horizontalCenter
                                cellW: 18; cellH: 22
                                readonly property string tok: page.sequence.length ? page.sequence[(page.chordIdx + 1) % page.sequence.length] : "C"
                                chord: Examples.chordName(tok)
                                voicing: Examples.voicing(page.song, tok)
                            }
                        }
                    }
                    // Sequência com o acorde atual marcado.
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: page.sequence
                            Rectangle {
                                required property string modelData
                                required property int index
                                readonly property bool cur: index === page.chordIdx && page.beat >= 0
                                width: chordLbl.implicitWidth + 14
                                height: chordLbl.implicitHeight + 8
                                radius: Theme.radiusSmall
                                color: cur ? Theme.chord : Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, 0.12)
                                Text {
                                    id: chordLbl
                                    anchors.centerIn: parent
                                    text: Examples.chordName(parent.modelData)
                                    color: parent.cur ? Theme.window : Theme.chord
                                    font.family: Theme.monoFamily
                                    font.pixelSize: Theme.fontSize
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: page.laps > 0 ? page.laps + (page.laps === 1 ? " volta completa  " : " voltas completas  ") + page.starText(page.lapStars) : "Troque de acorde na bolinha laranja (primeiro tempo)."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        AppButton {
                            text: page.running ? "Parar" : "Começar"
                            suggested: !page.running
                            onClicked: {
                                if (page.running) {
                                    if (page.lapStars > 0) page.record(0, page.lapStars)
                                    page.lapStars = 0
                                    page.stopClock()
                                } else {
                                    page.laps = 0
                                    page.startClock(8)
                                }
                            }
                        }
                    }
                }

                // ================= Quiz =================
                Card {
                    visible: page.mode === "quiz" && page.qIndex < page.questions.length
                    width: parent.width
                    readonly property var q: page.questions.length ? page.questions[Math.min(page.qIndex, page.questions.length - 1)] : null
                    id: quizCard
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: "Pergunta " + (page.qIndex + 1) + " de " + page.questions.length
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            text: (page.qCombo >= 3 ? "🔥 " + page.qCombo + " seguidas   " : "") + page.qRight + " certas"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: quizCard.q && quizCard.q.type === "name" ? "Que acorde é este?" : "Qual é a forma de " + (quizCard.q ? Examples.chordName(quizCard.q.token) : "") + "?"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 4
                        font.weight: Font.Bold
                    }
                    // Pergunta pelo desenho: diagrama grande + nomes.
                    BigChordDiagram {
                        visible: !!quizCard.q && quizCard.q.type === "name"
                        anchors.horizontalCenter: parent.horizontalCenter
                        chord: quizCard.q ? Examples.chordName(quizCard.q.token) : "C"
                        voicing: quizCard.q ? Examples.voicing(page.song, quizCard.q.token) : null
                    }
                    Grid {
                        visible: !!quizCard.q && quizCard.q.type === "name"
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 2
                        spacing: 10
                        Repeater {
                            model: quizCard.q && quizCard.q.type === "name" ? quizCard.q.options : []
                            Rectangle {
                                required property string modelData
                                readonly property bool isRight: Examples.chordName(modelData) === Examples.chordName(quizCard.q.token)
                                width: 160; height: 54
                                radius: Theme.radius
                                color: page.picked === "" ? Theme.button
                                     : isRight ? Theme.success
                                     : page.picked === modelData ? Theme.destructive : Theme.button
                                Text {
                                    anchors.centerIn: parent
                                    text: Examples.chordName(parent.modelData)
                                    color: Theme.text
                                    font.family: Theme.monoFamily
                                    font.pixelSize: 22
                                    font.weight: Font.Bold
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.answer(parent.modelData) }
                            }
                        }
                    }
                    // Pergunta pelo nome: quatro desenhos.
                    Grid {
                        visible: !!quizCard.q && quizCard.q.type === "shape"
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 4
                        spacing: 10
                        Repeater {
                            model: quizCard.q && quizCard.q.type === "shape" ? quizCard.q.options : []
                            Rectangle {
                                required property string modelData
                                readonly property bool isRight: Examples.chordName(modelData) === Examples.chordName(quizCard.q.token)
                                width: shapeD.implicitWidth + 20
                                height: shapeD.implicitHeight + 20
                                radius: Theme.radius
                                color: page.picked === "" ? Theme.button
                                     : isRight ? Theme.success
                                     : page.picked === modelData ? Theme.destructive : Theme.button
                                ChordDiagram {
                                    id: shapeD
                                    anchors.centerIn: parent
                                    cellW: 20; cellH: 24
                                    chord: Examples.chordName(parent.modelData)
                                    voicing: Examples.voicing(page.song, parent.modelData)
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.answer(parent.modelData) }
                            }
                        }
                    }
                }
                // Resultado do quiz.
                Card {
                    visible: page.mode === "quiz" && page.questions.length > 0 && page.qIndex >= page.questions.length
                    width: parent.width
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.starText(page.starsFor(page.qRight * 10))
                        color: Theme.chord
                        font.pixelSize: 48
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.qRight + " de " + page.questions.length + " certas" + (page.quizRecord ? " · novo recorde!" : "")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 4
                        font.weight: Font.Bold
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        AppButton { text: "Jogar de novo"; suggested: true; onClicked: page.startQuiz() }
                        AppButton { text: "Voltar"; onClicked: page.leave() }
                    }
                }

                // ================= Batida no tempo =================
                Card {
                    visible: page.mode === "rhythm"
                    width: parent.width
                    readonly property int len: page.pattern.length
                    readonly property int slot: page.running && page.tick >= 0 ? page.tick % len : -1
                    readonly property int measure: page.running && page.tick >= 0 ? Math.floor(page.tick / len) + 1 : 0
                    id: rhythmCard
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !page.running ? (page.rhythmResult ? "" : "Aperte Começar. Depois de 1 compasso de contagem, toque em cada seta.")
                              : page.tick < 0 ? "Contagem... " + Math.ceil(-page.tick / 2)
                              : "Compasso " + Math.min(rhythmCard.measure, page.measures) + " de " + page.measures
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4
                        Repeater {
                            model: page.pattern
                            Rectangle {
                                required property string modelData
                                required property int index
                                width: 52; height: 70
                                radius: Theme.radiusSmall
                                color: rhythmCard.slot === index ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3) : "transparent"
                                border.width: rhythmCard.slot === index ? 2 : 0
                                border.color: Theme.accent
                                Column {
                                    anchors.centerIn: parent
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Examples.strokeArrow(modelData)
                                        color: modelData === "" ? Theme.textDim : Theme.accent
                                        font.pixelSize: 30
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: (page.strums[Math.min(page.strumIndex, page.strums.length - 1)].counts || [])[index] || ""
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                    }
                                }
                            }
                        }
                    }
                    // Botão grande para tocar com o mouse/dedo.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, 360); height: 90
                        radius: Theme.radius
                        color: padMouse.pressed ? Theme.accent : Theme.button
                        Text {
                            anchors.centerIn: parent
                            text: page.flash !== "" ? page.flash : (page.running ? "Toque aqui ou Espaço" : "—")
                            color: page.flash === "Perfeito!" ? Theme.success : page.flash === "Fora do tempo" ? Theme.destructive : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            font.weight: Font.Bold
                        }
                        MouseArea { id: padMouse; anchors.fill: parent; onPressed: page.tap() }
                    }
                    // Resultado da rodada.
                    Column {
                        visible: !page.running && !!page.rhythmResult
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.rhythmResult ? page.starText(page.starsFor(page.rhythmResult.score)) : ""
                            color: Theme.chord
                            font.pixelSize: 44
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.rhythmResult ? page.rhythmResult.score + "% no tempo" + (page.rhythmRecord ? " · novo recorde!" : "") : ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 4
                            font.weight: Font.Bold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            readonly property var h: page.rhythmResult ? page.rhythmResult.hits : []
                            text: page.rhythmResult
                                  ? h.filter(function (x) { return x === 2 }).length + " perfeitas · "
                                    + h.filter(function (x) { return x === 1 }).length + " boas · "
                                    + h.filter(function (x) { return x === 0 }).length + " perdidas · "
                                    + page.rhythmResult.extra + " fora"
                                  : ""
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                    }
                    AppButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.running ? "Parar" : (page.rhythmResult ? "Jogar de novo" : "Começar")
                        suggested: !page.running
                        onClicked: page.running ? page.stopClock() : page.startRhythm()
                    }
                }

                Item { width: 1; height: 12 }
            }
        }
    }
}
