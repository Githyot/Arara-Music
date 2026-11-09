import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtMultimedia
import AraraCypher
import io.github.arara as Arara

// Modo Estudar do Arara Music: a cifra do Arara Cypher junto com a música
// tocando no player do Arara. A letra sincronizada acompanha a música, as
// partes da cifra acendem conforme a música anda (depois de marcadas uma
// vez), dá para repetir um trecho (loop A–B) e ligar ou desligar o som da
// música para tocar junto ou treinar o ouvido.
//
// Esta tela não conhece o player: recebe posição, duração, estado e letra
// por propriedades e pede as ações por sinais (o Main.qml do Arara liga tudo).
Rectangle {
    id: practice
    color: Theme.window

    // ---- Vindo do Arara ----
    property var track: null            // faixa da biblioteca do Arara
    property var sheet: null            // cifra do Arara Cypher (JSON)
    property real position: 0           // ms
    property real duration: 0           // ms
    property bool playing: false
    property bool loading: false        // a música ainda está abrindo
    property var lyrics: ({ kind: "none" })
    property bool lyricsLoading: false
    property real rate: 1
    property bool backing: true         // som da música ligado
    // Guardar o estado do estudo de cada faixa: { get(key, def), set(key, value) }.
    property var store: null

    signal seek(real ms)
    signal togglePlay()
    signal requestRate(real rate)
    signal requestBacking(bool on)
    signal editSheet(var sheet)
    signal openStudies()

    // ---- Estado do estudo desta faixa (loop e partes marcadas) ----
    property real loopA: -1
    property real loopB: -1
    property bool loopOn: false
    property int loopCount: 0
    property var marks: []              // [{ s: índice da parte, t: ms }] em ordem de tempo
    property bool marking: false
    property bool hideChords: false     // treino de ouvido: adivinhar os acordes da parte
    property bool revealed: false
    readonly property string storeKey: track ? "study:" + track.id : ""

    onStoreKeyChanged: restore()
    function restore() {
        loopA = -1; loopB = -1; loopOn = false; loopCount = 0; marks = []; marking = false
        if (!store || !storeKey) return
        try {
            var st = JSON.parse(store.get(storeKey, "null"))
            if (!st) return
            loopA = st.a >= 0 ? st.a : -1
            loopB = st.b > loopA ? st.b : -1
            marks = (st.marks || []).filter(function (m) { return m.s >= 0 && m.t >= 0 })
        } catch (e) {}
    }
    function persist() {
        if (!store || !storeKey) return
        store.set(storeKey, JSON.stringify({ a: loopA, b: loopB, marks: marks }))
    }

    // ---- Loop A–B ----
    property double jumpedAt: 0
    readonly property bool hasLoop: loopA >= 0 && loopB > loopA
    function jump(ms) { jumpedAt = Date.now(); seek(ms) }
    function setA() {
        loopA = Math.max(0, position - 150)
        if (loopB <= loopA) loopB = -1
        persist()
    }
    function setB() {
        if (loopA < 0) loopA = 0
        if (position <= loopA + 500) return
        loopB = position
        loopOn = true; loopCount = 0
        persist()
        jump(loopA)
    }
    function clearLoop() { loopA = -1; loopB = -1; loopOn = false; loopCount = 0; persist() }
    function loopSection(i) {
        // De onde a parte começa até a próxima parte marcada.
        // A vez dessa parte que está tocando (ou a última antes daqui); se
        // ela ainda não tocou, a primeira vez dela.
        var idx = -1
        for (var j = 0; j < marks.length; ++j) {
            if (marks[j].s !== i) continue
            if (marks[j].t <= position + 50 || idx < 0) idx = j
            if (marks[j].t > position + 50) break
        }
        if (idx < 0) return
        loopA = marks[idx].t
        loopB = idx + 1 < marks.length ? marks[idx + 1].t : duration - 200
        loopOn = true; loopCount = 0
        persist()
        jump(loopA)
        if (!playing) play()
    }
    onPositionChanged: {
        if (!loopOn || !hasLoop) return
        if (Date.now() - jumpedAt < 700) return
        if (position >= loopB) { loopCount++; jump(loopA) }
    }

    // ---- Partes marcadas ----
    readonly property int activeMark: {
        var lo = 0, hi = marks.length - 1, ans = -1
        while (lo <= hi) { var mid = (lo + hi) >> 1; if (marks[mid].t <= position) { ans = mid; lo = mid + 1 } else hi = mid - 1 }
        return ans
    }
    readonly property int activeSection: activeMark >= 0 ? marks[activeMark].s : -1
    readonly property int nextSection: activeMark + 1 < marks.length ? marks[activeMark + 1].s : -1
    onActiveSectionChanged: revealed = false
    function mark(i) {
        var m = marks.filter(function (x) { return Math.abs(x.t - position) > 400 })
        m.push({ s: i, t: Math.round(position) })
        m.sort(function (a, b) { return a.t - b.t })
        marks = m
        persist()
    }
    function undoMark() {
        if (!marks.length) return
        // Tira a última marcada antes de onde a música está (ou a última de todas).
        var idx = activeMark >= 0 ? activeMark : marks.length - 1
        var m = marks.slice(); m.splice(idx, 1); marks = m
        persist()
    }
    function clearMarks() { marks = []; persist() }

    // ---- Letra sincronizada do Arara ----
    readonly property var lines: lyrics && lyrics.kind === "synced" ? lyrics.lines : []
    readonly property int lineIndex: {
        var ls = lines, lo = 0, hi = ls.length - 1, ans = -1
        while (lo <= hi) { var mid = (lo + hi) >> 1; if (ls[mid].t <= position) { ans = mid; lo = mid + 1 } else hi = mid - 1 }
        return ans
    }
    function lineText(l) {
        if (!l) return ""
        if (l.text !== undefined && l.text !== null) return l.text
        if (l.words) return l.words.map(function (w) { return w.text !== undefined ? w.text : w.w }).join("")
        return ""
    }

    function fmt(ms) {
        var t = Math.max(0, Math.round(ms / 1000))
        return Math.floor(t / 60) + ":" + ("0" + (t % 60)).slice(-2)
    }
    readonly property var sections: sheet && sheet.sections ? sheet.sections : []
    function chordsOf(i) {
        var sec = sections[i]
        if (!sec) return []
        return sheetView.partChords(sec).map(function (c) { return sheetView.t(Examples.chordName(c)) })
    }

    // ---- Contagem antes do play (0 a 5 s), para dar tempo de pegar o instrumento ----
    property int countIn: 0
    property int countLeft: 0
    readonly property bool counting: countLeft > 0
    Component.onCompleted: { if (store) countIn = Math.max(0, Math.min(5, Number(store.get("study:countin", "0")) || 0)) }
    function cycleCountIn() {
        countIn = (countIn + 1) % 6
        if (store) store.set("study:countin", String(countIn))
    }
    function play() {
        // Pausar (ou cancelar a contagem) é na hora; começar espera a contagem.
        if (counting) { countLeft = 0; countTimer.stop(); return }
        if (playing || countIn === 0) { togglePlay(); return }
        countLeft = countIn
        tick.play()
        countTimer.restart()
    }
    Timer {
        id: countTimer
        interval: 1000
        repeat: true
        onTriggered: {
            practice.countLeft--
            if (practice.countLeft <= 0) { stop(); if (!practice.playing) practice.togglePlay() }
            else tick.play()
        }
    }
    SoundEffect { id: tick; source: Arara.CypherMusic.clickSound(true); volume: 0.6 }
    onTrackChanged: { countLeft = 0; countTimer.stop() }

    Keys.onSpacePressed: play()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ================= Barra de estudo =================
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: bar.implicitHeight + 20
            color: Theme.headerBar
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.36) : Qt.rgba(0, 0, 0, 0.12)
            }
            ColumnLayout {
                id: bar
                x: 16; y: 10
                width: parent.width - 32
                spacing: 8

                // Título, música de fundo e velocidade
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    RoundButton_ {
                        icon: practice.playing || practice.counting ? "pause" : "play"
                        big: true
                        suggested: true
                        onClicked: practice.play()
                    }
                    RoundButton_ { icon: "rewind"; onClicked: practice.jump(Math.max(0, practice.position - 5000)) }
                    Column {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: practice.track ? practice.track.title : ""
                            color: Theme.text
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize + 2; font.weight: Font.Bold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: (practice.track && practice.track.artist ? practice.track.artist + " · " : "")
                                  + (practice.sheet && practice.sheet.key ? "Tom " + sheetView.t(practice.sheet.key) + " · " : "")
                                  + (practice.loading ? "abrindo a música…" : practice.fmt(practice.position) + " / " + practice.fmt(practice.duration))
                            color: Theme.textDim
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                        }
                    }
                    // Som da música: tocar junto com ela ou treinar sem ela.
                    Pill {
                        icon: practice.backing ? "speaker" : "mute"
                        text: practice.backing ? "Som da música" : "Sem a música"
                        checked: practice.backing
                        tip: practice.backing ? "Toque junto com a gravação" : "A música continua andando em silêncio: a letra e as partes seguem, você toca sozinho"
                        onClicked: practice.requestBacking(!practice.backing)
                    }
                    SegmentedControl {
                        visible: practice.width > 760
                        model: [{ value: "0.5", label: "50%" }, { value: "0.75", label: "75%" }, { value: "0.9", label: "90%" }, { value: "1", label: "100%" }]
                        current: String(Math.round(practice.rate * 100) / 100)
                        onActivated: (v) => practice.requestRate(Number(v))
                    }
                    AppButton {
                        text: "Editar cifra"
                        flat: true
                        visible: practice.width > 960
                        onClicked: practice.editSheet(practice.sheet)
                    }
                }

                // Linha do tempo com o trecho A–B e as partes marcadas
                Item {
                    id: timeline
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    readonly property real frac: practice.duration > 0 ? Math.min(1, practice.position / practice.duration) : 0
                    function xOf(ms) { return practice.duration > 0 ? width * Math.max(0, Math.min(1, ms / practice.duration)) : 0 }
                    Rectangle {
                        id: track_
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 6; radius: 3
                        color: Theme.button
                    }
                    // Partes marcadas
                    Repeater {
                        model: practice.marks
                        Rectangle {
                            required property var modelData
                            required property int index
                            x: timeline.xOf(modelData.t)
                            width: (index + 1 < practice.marks.length ? timeline.xOf(practice.marks[index + 1].t) : timeline.width) - x
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6
                            color: index % 2 ? Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, 0.25) : Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, 0.42)
                            Rectangle { width: 2; height: 14; anchors.verticalCenter: parent.verticalCenter; color: Theme.chord; radius: 1 }
                        }
                    }
                    // Trecho A–B
                    Rectangle {
                        visible: practice.loopA >= 0
                        x: timeline.xOf(practice.loopA)
                        width: practice.hasLoop ? timeline.xOf(practice.loopB) - x : 2
                        anchors.verticalCenter: parent.verticalCenter
                        height: 18; radius: 4
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, practice.loopOn ? 0.30 : 0.16)
                        border.color: Theme.accent; border.width: 1
                    }
                    Rectangle {
                        width: timeline.frac * parent.width; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.accent
                        opacity: 0.85
                    }
                    Rectangle {
                        x: timeline.frac * parent.width - 7
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7
                        color: "white"
                        border.color: Qt.rgba(0, 0, 0, 0.25)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (e) => practice.jump(practice.duration * Math.max(0, Math.min(1, e.x / width)))
                        onPositionChanged: (e) => { if (pressed) practice.jump(practice.duration * Math.max(0, Math.min(1, e.x / width))) }
                    }
                }

                // Loop, marcar partes e treino de ouvido
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Pill {
                        icon: "play"
                        text: practice.countIn > 0 ? "Contagem " + practice.countIn + " s" : "Sem contagem"
                        checked: practice.countIn > 0
                        tip: "Tempo antes da música começar quando você dá o play (clique para mudar: 0 a 5 s)"
                        onClicked: practice.cycleCountIn()
                    }
                    Pill { text: practice.loopA >= 0 ? "A " + practice.fmt(practice.loopA) : "Marcar A"; tip: "Começo do trecho para repetir"; onClicked: practice.setA() }
                    Pill { text: practice.hasLoop ? "B " + practice.fmt(practice.loopB) : "Marcar B"; tip: "Fim do trecho: a música volta para o A"; onClicked: practice.setB() }
                    Pill {
                        visible: practice.hasLoop
                        icon: "loop"
                        text: practice.loopOn ? (practice.loopCount > 0 ? "Repetindo · " + practice.loopCount + "×" : "Repetindo") : "Repetir trecho"
                        checked: practice.loopOn
                        onClicked: { practice.loopOn = !practice.loopOn; practice.loopCount = 0; if (practice.loopOn) practice.jump(practice.loopA) }
                    }
                    Pill { visible: practice.loopA >= 0; text: "Limpar trecho"; flat: true; onClicked: practice.clearLoop() }
                    Item { width: 8; height: 1 }
                    Pill {
                        icon: "flag"
                        text: practice.marking ? "Pronto" : (practice.marks.length ? "Remarcar partes" : "Sincronizar partes")
                        checked: practice.marking
                        tip: "Com a música tocando, toque no nome de cada parte quando ela começar. Fica salvo para a próxima vez."
                        onClicked: practice.marking = !practice.marking
                    }
                    Pill {
                        icon: "eye"
                        text: "Treino de ouvido"
                        checked: practice.hideChords
                        tip: "Esconde os acordes da parte que está tocando: tente tirar de ouvido e depois confira"
                        onClicked: { practice.hideChords = !practice.hideChords; practice.revealed = false }
                    }
                }
            }
        }

        // ================= Partes (marcar e pular) =================
        Rectangle {
            visible: practice.sections.length > 0 && (practice.marking || practice.marks.length > 0)
            Layout.fillWidth: true
            implicitHeight: partsCol.implicitHeight + 16
            color: practice.marking ? Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, Theme.dark ? 0.14 : 0.08) : Theme.window
            Column {
                id: partsCol
                x: 16; y: 8
                width: parent.width - 32
                spacing: 6
                Text {
                    visible: practice.marking
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: practice.playing ? "Toque na parte que está começando agora. Errou? Use Desfazer."
                                           : "Dê o play e toque em cada parte quando ela começar."
                    color: Theme.text
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: practice.sections
                        Pill {
                            required property var modelData
                            required property int index
                            text: modelData.name + (modelData.repeat > 1 ? " " + modelData.repeat + "×" : "")
                            checked: index === practice.activeSection
                            accent: Theme.chord
                            enabled: practice.marking || practice.marks.some(function (m) { return m.s === index })
                            tip: practice.marking ? "Marca o começo desta parte em " + practice.fmt(practice.position) : "Repetir esta parte"
                            onClicked: practice.marking ? practice.mark(index) : practice.loopSection(index)
                        }
                    }
                    Pill { visible: practice.marking && practice.marks.length > 0; text: "Desfazer"; flat: true; onClicked: practice.undoMark() }
                    Pill { visible: practice.marking && practice.marks.length > 0; text: "Apagar marcas"; flat: true; onClicked: practice.clearMarks() }
                }
            }
        }

        // ================= Cifra + letra =================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            SongPage {
                id: sheetView
                Layout.fillWidth: true
                Layout.fillHeight: true
                embedded: true
                song: practice.sheet
                activeSection: practice.activeSection
                concealActive: practice.hideChords && !practice.revealed
                onEdit: practice.editSheet(practice.sheet)
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: practice.width > 1000 ? 360 : practice.width > 760 ? 290 : 0
                visible: Layout.preferredWidth > 0
                color: Theme.view
                Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.border }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 1
                    spacing: 0

                    // Agora: parte da vez e os acordes dela
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: nowCol.implicitHeight + 24
                        color: "transparent"
                        Column {
                            id: nowCol
                            x: 16; y: 12
                            width: parent.width - 32
                            spacing: 6
                            Text {
                                text: practice.activeSection >= 0 ? "Agora · " + practice.sections[practice.activeSection].name
                                     : practice.marks.length ? "Antes da primeira parte" : "Partes ainda não sincronizadas"
                                color: Theme.textDim
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1; font.weight: Font.DemiBold
                            }
                            Flow {
                                width: parent.width
                                spacing: 6
                                visible: practice.activeSection >= 0
                                Repeater {
                                    model: practice.activeSection >= 0 ? practice.chordsOf(practice.activeSection) : []
                                    Rectangle {
                                        required property var modelData
                                        readonly property bool hidden: practice.hideChords && !practice.revealed
                                        width: chordLabel.implicitWidth + 18; height: 34; radius: Theme.radiusSmall
                                        color: Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, hidden ? 0.08 : 0.16)
                                        Text {
                                            id: chordLabel
                                            anchors.centerIn: parent
                                            text: parent.hidden ? "?" : parent.modelData
                                            color: Theme.chord
                                            font.family: Theme.monoFamily; font.pixelSize: Theme.fontSize + 4; font.bold: true
                                        }
                                    }
                                }
                                AppButton {
                                    visible: practice.hideChords && !practice.revealed && practice.activeSection >= 0
                                    text: "Conferir"
                                    flat: true
                                    onClicked: practice.revealed = true
                                }
                            }
                            Text {
                                visible: practice.nextSection >= 0
                                width: parent.width
                                elide: Text.ElideRight
                                text: practice.nextSection >= 0 ? "Depois: " + practice.sections[practice.nextSection].name
                                      + (practice.hideChords ? "" : " · " + practice.chordsOf(practice.nextSection).join("  ")) : ""
                                color: Theme.textDim
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                visible: practice.marks.length === 0 && !practice.marking
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "Use Sincronizar partes uma vez e a cifra passa a acompanhar a música sozinha."
                                color: Theme.textDim
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
                            }
                        }
                        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 } height: 1; color: Theme.border }
                    }

                    // Letra sincronizada
                    ListView {
                        id: lyricList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        visible: practice.lines.length > 0
                        model: practice.lines
                        spacing: 10
                        topMargin: height * 0.3
                        bottomMargin: height * 0.5
                        // A linha da vez fica a um terço da altura, sem pular.
                        function follow() {
                            var it = itemAtIndex(Math.max(0, practice.lineIndex))
                            if (!it) { positionViewAtIndex(Math.max(0, practice.lineIndex), ListView.Center); return }
                            var target = practice.lineIndex < 0 ? -topMargin : it.y - height * 0.3
                            follower.to = Math.max(-topMargin, Math.min(contentHeight - height + bottomMargin, target))
                            follower.restart()
                        }
                        NumberAnimation { id: follower; target: lyricList; property: "contentY"; duration: 380; easing.type: Easing.OutCubic }
                        Connections { target: practice; function onLineIndexChanged() { if (!lyricList.moving) lyricList.follow() } }
                        onHeightChanged: Qt.callLater(follow)
                        ScrollBar.vertical: AppScrollBar {}
                        delegate: Text {
                            required property var modelData
                            required property int index
                            readonly property bool current: index === practice.lineIndex
                            x: 18
                            width: lyricList.width - 36
                            wrapMode: Text.WordWrap
                            text: practice.lineText(modelData) || "♪"
                            color: current ? Theme.text : index < practice.lineIndex ? Theme.textDim : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.62)
                            font.family: Theme.fontFamily
                            font.pixelSize: current ? Theme.fontSize + 6 : Theme.fontSize + 2
                            font.weight: current ? Font.Bold : Font.Normal
                            Behavior on font.pixelSize { NumberAnimation { duration: 160 } }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: practice.jump(parent.modelData.t)
                            }
                        }
                    }
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: practice.lines.length === 0
                        clip: true
                        contentHeight: plainText.implicitHeight + 32
                        ScrollBar.vertical: AppScrollBar {}
                        Text {
                            id: plainText
                            x: 18; y: 16
                            width: parent.width - 36
                            wrapMode: Text.WordWrap
                            lineHeight: 1.3
                            text: practice.lyricsLoading ? "Procurando a letra…"
                                : practice.lyrics && practice.lyrics.kind === "plain" ? (practice.lyrics.text || "")
                                : "Esta música não tem letra sincronizada. A cifra e o loop funcionam do mesmo jeito."
                            color: practice.lyrics && practice.lyrics.kind === "plain" ? Theme.text : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: practice.lyrics && practice.lyrics.kind === "plain" ? Theme.fontSize + 1 : Theme.fontSize - 1
                        }
                    }
                }
            }
        }
    }

    // Número grande da contagem, por cima da cifra.
    Rectangle {
        visible: practice.counting
        anchors.centerIn: parent
        width: 150; height: 150; radius: 75
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.92)
        Text {
            anchors.centerIn: parent
            text: practice.countLeft
            color: Theme.accentFg
            font.family: Theme.fontFamily; font.pixelSize: 72; font.bold: true
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 10 }
            text: "Prepare-se…"
            color: Theme.text
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize + 2; font.weight: Font.DemiBold
        }
    }

    // ---- Pecinhas ----
    component Pill: Rectangle {
        id: pill
        property string text
        property string icon: ""
        property string tip: ""
        property bool checked: false
        property bool flat: false
        property color accent: Theme.accent
        signal clicked()
        implicitWidth: pillRow.implicitWidth + 22
        implicitHeight: 32
        width: implicitWidth; height: implicitHeight
        radius: Theme.apple ? height / 2 : Theme.radiusSmall
        opacity: enabled ? 1 : 0.45
        color: checked ? Qt.rgba(accent.r, accent.g, accent.b, Theme.dark ? 0.30 : 0.16)
             : flat ? (pillMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06) : "transparent")
             : pillMouse.containsMouse ? Theme.buttonHover : Theme.button
        border.width: checked ? 1 : 0
        border.color: accent
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Icon { visible: pill.icon !== ""; name: pill.icon; size: 14; color: pill.checked ? pill.accent : Theme.text; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: pill.text
                color: pill.checked ? pill.accent : Theme.text
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1; font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea { id: pillMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
        ToolTip.visible: tip !== "" && pillMouse.containsMouse
        ToolTip.delay: 700
        ToolTip.text: tip
    }
    component RoundButton_: Rectangle {
        id: rb
        property string icon
        property bool big: false
        property bool suggested: false
        signal clicked()
        width: big ? 44 : 34; height: width; radius: width / 2
        color: suggested ? (rbMouse.pressed ? Qt.darker(Theme.accent, 1.15) : Theme.accent)
             : rbMouse.containsMouse ? Theme.buttonHover : Theme.button
        Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: rb.icon === "play" ? 1 : 0; name: rb.icon; size: rb.big ? 18 : 14; color: rb.suggested ? Theme.accentFg : Theme.text }
        MouseArea { id: rbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }
}
