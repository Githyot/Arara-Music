import QtQuick
import AraraCypher
import io.github.arara as Arara

// Visão "Tudo" de um trecho: cada acorde num quadro com o braço (detalhado)
// e, embaixo, o pedaço da partitura + tab tocado nele. Se o trecho tem tab
// (riff), ela é cortada nos pontos em que muda o acorde; se não tem, o quadro
// mostra a partitura e a tab colorida da batida.
Flow {
    id: root
    property var section: null         // a parte de verdade
    property var song: null
    property var strum: null
    property int semitones: 0
    property real zoom: 1
    property string keyName: "C"
    property int rev: 0
    property bool editing: false       // mostra "Editar braço" em cada quadro
    signal edited()
    spacing: 10

    // Forma própria desta música para o acorde (cria a partir da do app).
    function ownVoicing(token) {
        if (!song) return null
        if (!song.voicings) song.voicings = {}
        if (!song.voicings[token]) {
            var s = Examples.shape(Examples.chordName(token), 0, null)
            song.voicings[token] = s ? { frets: s.frets.slice(), fingers: s.fingers.slice() }
                                     : { frets: [-1, -1, -1, -1, -1, -1], fingers: [0, 0, 0, 0, 0, 0] }
        }
        return song.voicings[token]
    }

    // Quadros do mesmo tamanho, dois (ou mais, em tela larga) por linha.
    readonly property int cols: Math.max(1, Math.floor((width + spacing) / (330 * zoom + spacing)))
    readonly property real boxW: (width - (cols - 1) * spacing) / cols
    // Quadro fechado (só o braço): menor, vários por linha, mesmo tamanho.
    readonly property int smallCols: Math.max(1, Math.floor((width + spacing) / (190 * zoom + spacing)))
    readonly property real smallW: (width - (smallCols - 1) * spacing) / smallCols
    // Largura de cada toque para um pedaço caber no quadro (18 a 24).
    function slotFor(events, bars, w) {
        return Math.max(18, Math.min(24, (w / zoom - 68 - bars * 12) / Math.max(1, events)))
    }
    function fitsBox(events, bars) {
        return (68 + events * 18 + bars * 12) * zoom <= boxW - 16
    }

    function t(name) { return Arara.CypherMusic.transposeChord(name, semitones) }

    // Pedaços da tab: [{ name, tab, events }] na ordem.
    readonly property var segments: {
        if (!section || !section.tab) return []
        var systems = JSON.parse(Arara.CypherMusic.tabModel(section.tab))
        var out = [], nextChord = 0
        for (var s = 0; s < systems.length; ++s) {
            var sys = systems[s]
            var chords = (sys.chords || []).slice().sort(function (a, b) { return a.at - b.at })
            var cuts = chords.map(function (c) { return c.at })
            if (cuts.length === 0 || cuts[0] > 0) {
                cuts.unshift(0)
                chords.unshift({ at: 0, name: out.length ? out[out.length - 1].name : "" })
            }
            for (var i = 0; i < cuts.length; ++i) {
                var a = cuts[i], b = i + 1 < cuts.length ? cuts[i + 1] : sys.events.length
                if (b <= a) continue
                var sub = {
                    chords: [],
                    events: sys.events.slice(a, b),
                    bars: (sys.bars || []).filter(function (x) { return x > a && x < b }).map(function (x) { return x - a })
                }
                out.push({ name: chords[i].name, tab: Arara.CypherMusic.renderTab(JSON.stringify([sub])), events: sub.events.length, bars: sub.bars.length })
            }
        }
        return out
    }
    // Sem tab: um quadro por acorde, com a batida da parte.
    // A tab manda: com tab, só aparecem os braços dos acordes marcados nela
    // (Acorde neste toque). Sem tab, um quadro por acorde da parte.
    readonly property var chordItems: !section || section.tab ? [] : (section.chords || [])
    function patternOf(i) {
        var base = strum ? strum.pattern : ["D"]
        var own = section && section.measures ? section.measures[i] : null
        return own && own.length === base.length ? own : base
    }
    function cellsOf(i) {
        var base = strum ? strum.pattern : ["D"]
        var own = section && section.measures ? section.measures[i] : null
        return own && own.length === base.length && section.cells && section.cells[i] ? section.cells[i] : ({})
    }

    // Tab (pauta + TAB) da batida tocada num acorde: cada tempo vira um
    // toque com as cordas que soam e a seta embaixo. Usa as casas escritas
    // à mão no compasso (cells) por cima da forma.
    function strumEvents(i, token) {
        var shape = Examples.shape(Examples.chordName(token), semitones, song ? Examples.voicing(song, token) : null) || Examples.blankShape()
        var pat = patternOf(i), cells = cellsOf(i)
        var events = []
        for (var k = 0; k < pat.length; ++k) {
            var code = pat[k]
            if (!code) continue
            var strings = Examples.isPick(code)
                ? Examples.pickStrings(code).filter(function (st) { return shape.frets[st] >= 0 || cells[k + ":" + st] })
                : Examples.strokeStrings(shape, code)
            var notes = []
            for (var j = 0; j < strings.length; ++j) {
                var st = strings[j], c = cells[k + ":" + st]
                var f = c && c.f !== undefined ? c.f : shape.frets[st]
                if (Examples.isMute(code)) f = 255
                if (f < 0) continue
                notes.push({ string: st, fret: f })
            }
            if (notes.length) events.push({ notes: notes, arrow: (Examples.isMute(code) ? Examples.plain(code) : Examples.strokeUp(code) ? "U" : "D") + (Examples.isAccent(code) ? ">" : "") })
        }
        return events
    }
    function strumTabText(i, token) {
        var events = strumEvents(i, token)
        return events.length ? Arara.CypherMusic.renderTab(JSON.stringify([{ chords: [], events: events, bars: [] }])) : ""
    }
    // A parte inteira, contínua: a tab dela, ou (sem tab) a batida de cada
    // acorde em seguida, com o nome em cima e barra entre um e outro.
    readonly property string fullTab: {
        rev
        if (!section) return ""
        if (section.tab) return section.tab
        var sys = { chords: [], events: [], bars: [] }
        var cs = section.chords || []
        for (var i = 0; i < cs.length; ++i) {
            var ev = strumEvents(i, cs[i])
            if (!ev.length) continue
            if (sys.events.length) sys.bars.push(sys.events.length)
            sys.chords.push({ at: sys.events.length, name: cs[i] })
            sys.events = sys.events.concat(ev)
        }
        return sys.events.length ? Arara.CypherMusic.renderTab(JSON.stringify([sys])) : ""
    }

    // ---- A parte inteira primeiro (partitura contínua) ----
    TabScore {
        width: root.width
        height: implicitHeight
        tab: root.fullTab
        showChords: true
        semitones: root.semitones
        keyName: root.keyName
        zoom: root.zoom
    }

    // ---- Com tab: pedaços ----
    Repeater {
        model: root.segments
        Rectangle {
            id: seg
            required property var modelData
            readonly property string name: modelData.name
            readonly property var voicing: root.rev, root.song ? Examples.voicing(root.song, name) : null
            property bool open: false
            property string applied: ""
            // Pedaço comprido demais para o quadro ocupa a linha toda.
            readonly property bool wide: !root.fitsBox(modelData.events, modelData.bars)
            // Só o braço; clicar no quadro mostra a partitura deste trecho.
            // Sem nome de acorde não há braço: mostra a partitura direto.
            property bool showScore: name === ""
            width: !showScore && !open ? root.smallW
                 : wide || (open && segEditor.implicitWidth + 16 > root.boxW) ? root.width : root.boxW
            height: col.implicitHeight + 16
            radius: Theme.radiusSmall
            color: Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, Theme.dark ? 0.12 : 0.07)
            MouseArea {
                anchors.fill: parent
                enabled: seg.name !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: seg.showScore = !seg.showScore
            }
            Column {
                id: col
                x: 8; y: 8
                width: parent.width - 16
                spacing: 4
                Text {
                    id: title
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: seg.name !== ""
                    text: root.t(Examples.chordName(seg.name))
                    color: Theme.chord
                    font.family: Theme.monoFamily
                    font.pixelSize: (Theme.fontSize + 4) * root.zoom
                    font.weight: Font.Bold
                }
                Item {
                    visible: diag.visible
                    width: parent.width
                    height: diag.implicitHeight * root.zoom
                    BigChordDiagram {
                        id: diag
                        visible: seg.name !== "" && shape !== null
                        scale: root.zoom
                        transformOrigin: Item.Top
                        anchors.horizontalCenter: parent.horizontalCenter
                        chord: Examples.chordName(seg.name)
                        voicing: seg.voicing
                        semitones: root.semitones
                    }
                }
                AppButton {
                    visible: root.editing && seg.name !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: seg.open ? "Fechar editor de braço" : "Editar braço"
                    onClicked: { if (!seg.open) root.ownVoicing(seg.name); seg.open = !seg.open }
                }
                AppButton {
                    visible: root.editing && seg.open && !!root.section && !!root.section.tab
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Aplicar esta forma na tab"
                    onClicked: {
                        var v = root.ownVoicing(seg.name)
                        var r = Examples.applyShapeToTab(root.section.tab, seg.name, v.frets)
                        root.section.tab = r.tab
                        seg.applied = r.changed ? r.changed + " toques mudaram na tab." : "A tab já está com essa forma."
                        root.edited()
                    }
                }
                Text {
                    visible: root.editing && seg.open && seg.applied !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: seg.applied
                    color: Theme.success
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
                ChordEditor {
                    id: segEditor
                    visible: root.editing && seg.open
                    width: implicitWidth
                    voicing: seg.open ? root.ownVoicing(seg.name) : null
                    chord: seg.name
                    capo: root.song && root.song.fretsReal ? (root.song.capo || 0) : 0
                    rev: root.rev
                    onChanged: root.edited()
                }
                Text {
                    visible: seg.name !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: seg.showScore ? "▴ esconder partitura" : "▾ ver partitura"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                TabScore {
                    id: score
                    visible: seg.showScore && events.length > 0
                    // Pedaço comprido quebra em linhas dentro da largura da tela.
                    readonly property real avail: seg.width - 16
                    slotW: seg.wide ? 24 : root.slotFor(seg.modelData.events, seg.modelData.bars, avail)
                    width: Math.min(avail, (68 + seg.modelData.events * slotW + seg.modelData.bars * 12) * root.zoom)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: implicitHeight
                    tab: seg.modelData.tab
                    keyName: root.keyName
                    zoom: root.zoom
                }
            }
        }
    }

    // ---- Sem tab: acordes com a batida ----
    Repeater {
        model: root.chordItems
        Rectangle {
            id: box
            required property string modelData
            required property int index
            readonly property string name: Examples.chordName(modelData)
            readonly property var voicing: root.rev, root.song ? Examples.voicing(root.song, modelData) : null
            property bool open: false
            property bool showScore: false
            width: !showScore && !open ? root.smallW
                 : open && boxEditor.implicitWidth + 16 > root.boxW ? root.width : root.boxW
            height: inner.implicitHeight + 16
            radius: Theme.radiusSmall
            color: Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, Theme.dark ? 0.12 : 0.07)
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: box.showScore = !box.showScore
            }
            Column {
                id: inner
                x: 8; y: 8
                width: parent.width - 16
                spacing: 6
                Text {
                    id: label
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.t(box.name)
                    color: Theme.chord
                    font.family: Theme.monoFamily
                    font.pixelSize: (Theme.fontSize + 4) * root.zoom
                    font.weight: Font.Bold
                }
                Item {
                    visible: big.shape !== null
                    width: parent.width
                    height: big.implicitHeight * root.zoom
                    BigChordDiagram {
                        id: big
                        scale: root.zoom
                        transformOrigin: Item.Top
                        anchors.horizontalCenter: parent.horizontalCenter
                        chord: box.name
                        voicing: box.voicing
                        semitones: root.semitones
                    }
                }
                AppButton {
                    visible: root.editing
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: box.open ? "Fechar editor de braço" : "Editar braço"
                    onClicked: { if (!box.open) root.ownVoicing(box.modelData); box.open = !box.open }
                }
                ChordEditor {
                    id: boxEditor
                    visible: root.editing && box.open
                    width: implicitWidth
                    voicing: box.open ? root.ownVoicing(box.modelData) : null
                    chord: box.modelData
                    capo: root.song && root.song.fretsReal ? (root.song.capo || 0) : 0
                    rev: root.rev
                    onChanged: root.edited()
                }
                // A batida no estilo da tab: pauta + TAB com as setas.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: box.showScore ? "▴ esconder partitura" : "▾ ver partitura"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
                TabScore {
                    id: beatScore
                    visible: box.showScore && events.length > 0
                    readonly property string text: root.rev, root.strumTabText(box.index, box.modelData)
                    readonly property int steps: root.patternOf(box.index).filter(function (c) { return c !== "" }).length
                    slotW: root.slotFor(steps, 0, box.width - 16)
                    width: Math.min(box.width - 16, (68 + steps * slotW) * root.zoom)
                    height: implicitHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    tab: text
                    keyName: root.keyName
                    zoom: root.zoom
                }
            }
        }
    }
}
