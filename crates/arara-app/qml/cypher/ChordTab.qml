import QtQuick
import AraraCypher

// Tab colorida de uma parte (StrumStrip) com a mão dos dedos ao lado e,
// no modo de edição, o painel da nota escolhida: tocar numa casa muda o
// número, o dedo (a cor) ou se a corda toca; tocar numa seta troca o golpe.
// Não mexe na forma do acorde: o que se escreve fica no compasso
// (section.measures[i] e section.cells[i]). Avisa com edited().
Column {
    id: root
    property var song: null
    property var chords: []
    property var strum: null
    property var section: null          // a parte de verdade (não a cópia do Repeater)
    property int semitones: 0
    property real zoom: 1
    property int rev: 0
    property bool editing: false
    property string status: ""
    signal edited()

    property var sel: null              // { index, token, string, step }
    property int localRev: 0
    onEditingChanged: sel = null
    readonly property int allRev: rev + localRev
    // Tempos e casas de cada compasso numa cópia só, refeita a cada mudança.
    readonly property var view: {
        allRev
        return JSON.parse(JSON.stringify({ patterns: patterns(), cells: cellsList(), all: section ? [section.measures, section.cells] : [] }))
    }
    readonly property var strokeCodes: ["", "B", "D", "d", "U", "X", "XU"]

    function changed() { localRev++; edited() }

    // ---- Compasso próprio ----
    // A tab nasce da forma do acorde + batida. No primeiro clique num compasso
    // ele vira "próprio": cada tempo guarda as cordas que toca (section.measures)
    // e cada casa escrita fica em section.cells, só naquele lugar. Assim um
    // clique muda só a casa clicada, sem puxar nada da forma para outros tempos.
    function valid(index) {
        var base = strum ? strum.pattern : ["D"]
        var own = section && section.measures ? section.measures[index] : null
        return !!own && own.length === base.length
    }
    function patternOf(index) {
        return valid(index) ? section.measures[index] : (strum ? strum.pattern : ["D"])
    }
    function patterns() {
        var out = []
        for (var i = 0; i < chords.length; ++i) out.push(patternOf(i).slice())
        return out
    }
    function cellsOf(index) {
        return valid(index) && section.cells && section.cells[index] ? section.cells[index] : ({})
    }
    function cellsList() {
        var out = []
        for (var i = 0; i < chords.length; ++i) out.push(cellsOf(i))
        return out
    }
    function stepStrings(index, token, step) {
        var code = patternOf(index)[step]
        var sh = baseShape(token), cells = cellsOf(index)
        if (Examples.isPick(code))
            return Examples.pickStrings(code).filter(function (s) { return sh.frets[s] >= 0 || cells[step + ":" + s] })
        return Examples.strokeStrings(sh, code)
    }
    function ownPattern(index) {
        if (!section) return null
        if (valid(index)) return section.measures[index]
        if (!section.measures) section.measures = []
        if (!section.cells) section.cells = []
        while (section.measures.length < chords.length) section.measures.push(null)
        while (section.cells.length < chords.length) section.cells.push(null)
        var token = chords[index], sh = baseShape(token)
        var base = strum ? strum.pattern : ["D"]
        var own = base.map(function (code) {
            if (code === "" || Examples.isMute(code) || Examples.isPick(code)) return code
            var st = Examples.strokeStrings(sh, code)
            return st.length ? Examples.pickCode(st, Examples.strokeUp(code)) : (Examples.strokeUp(code) ? "PU" : "P")
        })
        section.measures[index] = own
        section.cells[index] = {}
        return own
    }
    function ownCells(index) {
        if (!ownPattern(index)) return {}
        if (!section.cells) section.cells = []
        while (section.cells.length <= index) section.cells.push(null)
        if (!section.cells[index]) section.cells[index] = {}
        return section.cells[index]
    }
    function key(step, string) { return step + ":" + string }

    // Casa e dedo de uma nota (a escrita à mão, senão a da forma).
    function fretAt(index, token, step, string) {
        var c = cellsOf(index)[key(step, string)]
        if (c && c.f !== undefined) return c.f
        var f = baseShape(token).frets[string]
        return f < 0 ? 0 : f
    }
    function fingerAt(index, token, step, string) {
        var c = cellsOf(index)[key(step, string)]
        if (c && c.g !== undefined) return c.g
        if (c && c.f !== undefined) return 0
        return baseShape(token).fingers[string] || 0
    }
    function setFret(fret) {
        if (!sel) return
        if (fret < 0) { removeFromStep(); return }
        addToStep()
        var cells = ownCells(sel.index)
        var k = key(sel.step, sel.string)
        var c = cells[k] || {}
        c.f = fret === 255 ? 255 : Math.min(24, fret)
        if (c.f === 0 || c.f === 255) c.g = 0
        cells[k] = c
        changed()
    }
    function setFinger(finger) {
        if (!sel) return
        addToStep()
        var cells = ownCells(sel.index)
        var k = key(sel.step, sel.string)
        var c = cells[k] || { f: fretAt(sel.index, sel.token, sel.step, sel.string) }
        c.g = finger
        cells[k] = c
        changed()
    }
    function cycleStroke(index, step) {
        var pat = ownPattern(index)
        if (!pat) return
        var strong = Examples.isAccent(pat[step])
        var code = Examples.plain(pat[step])
        if (Examples.isPick(code)) {
            // Dedilhado: a seta só vira (para baixo / para cima).
            var st = Examples.pickStrings(code)
            var up = !Examples.strokeUp(code)
            pat[step] = st.length ? Examples.pickCode(st, up) : (up ? "PU" : "P")
        } else {
            var i = strokeCodes.indexOf(code)
            pat[step] = strokeCodes[(i + 1) % strokeCodes.length]
        }
        pat[step] = Examples.withAccent(pat[step], strong)
        changed()
    }
    function baseShape(token) {
        return Examples.shape(Examples.chordName(token), 0, Examples.voicing(song, token)) || Examples.blankShape()
    }
    // Limpa o compasso (fica só com as setas) ou volta a seguir a batida.
    function clearMeasure(index) {
        var pat = ownPattern(index)
        if (!pat) return
        for (var j = 0; j < pat.length; ++j)
            if (pat[j] !== "") pat[j] = Examples.strokeUp(pat[j]) ? "PU" : "P"
        ownCells(index)
        section.cells[index] = {}
        changed()
    }
    function resetMeasure(index) {
        if (!section || !section.measures) return
        section.measures[index] = null
        if (section.cells) section.cells[index] = null
        changed()
    }

    // ---- Teclado ----
    // Com uma casa escolhida: números digitam a casa (dois dígitos seguidos
    // viram 10, 11...), Delete/Backspace tira do tempo, X = abafada (x),
    // setas andam entre cordas e tempos, Enter/Esc fecham.
    property string typed: ""
    Timer { id: typedTimer; interval: 900; onTriggered: root.typed = "" }
    function typeDigit(d) {
        if (!sel) return
        typed = typedTimer.running && typed.length === 1 && parseInt(typed + d) <= 24 ? typed + d : d
        typedTimer.restart()
        setFret(Math.min(24, parseInt(typed)))
    }
    function move(dString, dStep) {
        if (!sel) return
        var n = patternOf(sel.index).length
        var index = sel.index, step = sel.step + dStep
        if (step >= n && index < chords.length - 1) { index++; step = 0 }
        else if (step < 0 && index > 0) { index--; step = n - 1 }
        step = Math.max(0, Math.min(n - 1, step))
        var string = Math.max(0, Math.min(5, sel.string + dString))
        sel = { index: index, token: chords[index], string: string, step: step }
        typed = ""
    }
    focus: editing
    Keys.onPressed: (e) => {
        if (!editing || !sel) return
        if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) typeDigit(String(e.key - Qt.Key_0))
        else if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) removeFromStep()
        else if (e.key === Qt.Key_X) setFret(255)
        else if (e.key === Qt.Key_Left) move(0, -1)
        else if (e.key === Qt.Key_Right) move(0, 1)
        else if (e.key === Qt.Key_Up) move(1, 0)
        else if (e.key === Qt.Key_Down) move(-1, 0)
        else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) sel = null
        else return
        e.accepted = true
    }

    // Tocar numa casa: só escolhe. Uma casa vazia ganha a nota (casa 0, ou a
    // da forma do acorde) só naquele tempo.
    function tapCell(index, token, string, step) {
        forceActiveFocus()
        sel = { index: index, token: token, string: string, step: step }
        typed = ""
        if (stepStrings(index, token, step).indexOf(string) >= 0) return
        addToStep()
        changed()
    }
    function addToStep() {
        var strings = stepStrings(sel.index, sel.token, sel.step)
        if (strings.indexOf(sel.string) >= 0) return
        var pat = ownPattern(sel.index)
        if (!pat) return
        var code = pat[sel.step]
        strings = stepStrings(sel.index, sel.token, sel.step)
        var cells = ownCells(sel.index)
        var k = key(sel.step, sel.string)
        if (!cells[k]) cells[k] = { f: fretAt(sel.index, sel.token, sel.step, sel.string) }
        strings.push(sel.string)
        pat[sel.step] = Examples.pickCode(strings, Examples.strokeUp(code))
    }
    function removeFromStep() {
        if (!sel) return
        var pat = ownPattern(sel.index)
        if (!pat) return
        var code = pat[sel.step]
        var strings = stepStrings(sel.index, sel.token, sel.step).filter(function (s) { return s !== sel.string })
        var up = Examples.strokeUp(code)
        pat[sel.step] = strings.length ? Examples.pickCode(strings, up) : (code === "" ? "" : (up ? "PU" : "P"))
        delete ownCells(sel.index)[key(sel.step, sel.string)]
        changed()
    }

    spacing: 8

    Item {
        width: parent.width
        height: Math.max(strip.implicitHeight, hand.implicitHeight)
        HandLegend {
            id: hand
            anchors.right: parent.right
            zoom: Math.min(root.zoom, 1.2)
        }
        StrumStrip {
            id: strip
            width: parent.width - hand.width - 12
            chords: root.chords
            song: root.song
            // Na edição a tab fica no tom original (as casas salvas são as de verdade).
            semitones: root.editing ? 0 : root.semitones
            pattern: root.allRev, root.strum ? root.strum.pattern.slice() : ["D"]
            patterns: root.view.patterns
            cells: root.view.cells
            counts: root.strum ? root.strum.counts : []
            zoom: root.zoom
            rev: root.allRev
            editing: root.editing
            selIndex: root.sel ? root.sel.index : -1
            selString: root.sel ? root.sel.string : -1
            selStep: root.sel ? root.sel.step : -1
            onNoteClicked: (i, token, string, step) => root.tapCell(i, token, string, step)
            onStepClicked: (i, step) => root.cycleStroke(i, step)
        }
    }

    Column {
        id: notePanel
        visible: root.editing
        width: parent.width
        spacing: 8
        readonly property bool on: !!root.sel
        readonly property int fret: root.allRev, on ? root.fretAt(root.sel.index, root.sel.token, root.sel.step, root.sel.string) : 0
        readonly property int finger: root.allRev, on ? root.fingerAt(root.sel.index, root.sel.token, root.sel.step, root.sel.string) : 0
        Text {
            visible: !notePanel.on
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Toque num lugar vazio (+) para pôr uma nota só naquele tempo; toque num número para mudar a casa ou o dedo. Cada clique muda só aquela casa. Toque numa seta para trocar o golpe. Teclado: digite a casa, X = abafada, Delete tira, setas andam."
                  + (root.status ? " " + root.status : "")
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Flow {
            visible: notePanel.on
            width: parent.width
            spacing: 8
            Text {
                height: Theme.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: notePanel.on ? Examples.chordName(root.sel.token) + " · corda " + ["E", "A", "D", "G", "B", "e"][root.sel.string] : ""
                color: Theme.chord
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
            }
            Row {
                spacing: 4
                AppButton { iconName: "remove"; onClicked: root.setFret(notePanel.fret === 255 ? 0 : Math.max(0, notePanel.fret - 1)) }
                Text {
                    width: 64
                    height: Theme.controlHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: notePanel.fret === 255 ? "abafada (x)" : notePanel.fret === 0 ? "solta" : "casa " + notePanel.fret
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                AppButton { iconName: "add"; onClicked: root.setFret(notePanel.fret === 255 ? 1 : Math.min(24, notePanel.fret + 1)) }
            }
            Row {
                spacing: 4
                Repeater {
                    model: [0, 1, 2, 3, 4, 5]
                    Rectangle {
                        required property int modelData
                        readonly property bool chosen: notePanel.finger === modelData
                        readonly property bool usable: (notePanel.fret > 0 && notePanel.fret !== 255) || modelData === 0
                        width: Theme.controlHeight
                        height: Theme.controlHeight
                        radius: width / 2
                        opacity: usable ? 1 : 0.35
                        color: chosen ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Theme.button
                        border.width: chosen ? 3 : 2
                        border.color: modelData === 0 ? Theme.textDim : Theme.fingerColors[modelData]
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData === 0 ? "–" : parent.modelData === 5 ? "P" : parent.modelData
                            color: parent.modelData === 0 ? Theme.textDim : Theme.fingerColors[parent.modelData]
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.usable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setFinger(parent.modelData)
                        }
                    }
                }
            }
            AppButton {
                text: "Tirar deste tempo"
                onClicked: root.removeFromStep()
            }
            AppButton {
                flat: true
                text: notePanel.fret === 255 ? "Tirar o x" : "x (abafar)"
                onClicked: root.setFret(notePanel.fret === 255 ? 0 : 255)
            }
            AppButton {
                text: "Limpar compasso"
                flat: true
                onClicked: root.clearMeasure(root.sel.index)
            }
            AppButton {
                visible: root.allRev, notePanel.on && root.valid(root.sel.index)
                text: "Voltar à forma do acorde"
                flat: true
                onClicked: root.resetMeasure(root.sel.index)
            }
            AppButton { text: "Pronto"; flat: true; onClicked: root.sel = null }
            Text {
                height: Theme.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: root.status
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}
