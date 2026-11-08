import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import AraraCypher
import io.github.arara as Arara

// Editor visual da tab de uma parte. Mostra todos os toques (cada coluna da
// tab é um toque), com o acorde em cima e a seta embaixo. Toque numa coluna
// para escolher; o braço embaixo mostra as notas daquele toque e um toque
// numa casa põe, troca ou tira a nota. Arraste uma nota para outro toque ou
// outra corda; arraste o topo da coluna para mudar o toque de lugar. O texto
// da tab é gerado de novo a cada mudança (sempre alinhado, seta sob o toque).
Column {
    id: root
    property string text
    signal edited(string text)

    property var model: []             // [{ chords:[{at,name}], events:[{notes,arrow}], bars:[] }]
    property string lastText: "\u0000"
    property int curS: 0
    property int curE: 0
    property int curString: 5          // corda escolhida para o teclado
    property int selA: -1              // começo da seleção (no mesmo bloco); -1 = só o toque
    readonly property int selFrom: selA < 0 ? curE : Math.min(selA, curE)
    readonly property int selTo: selA < 0 ? curE : Math.max(selA, curE)
    readonly property int selCount: selTo - selFrom + 1

    // ---- Copiar e colar toques ----
    function copySel() {
        var s = sys(); if (!s || !s.events.length) return
        Examples.tabClip = JSON.parse(JSON.stringify(s.events.slice(selFrom, selTo + 1)))
        rev++
    }
    function cutSel() {
        copySel()
        var s = sys(); if (!s || !s.events.length) return
        var from = selFrom, n = selCount
        s.events.splice(from, n)
        shift(s, from + n, -n)
        selA = -1
        curE = Math.max(0, from - 1)
        if (s.events.length === 0) { model.splice(curS, 1); curS = Math.max(0, curS - 1); curE = 0 }
        commit()
    }
    function paste() {
        var clip = Examples.tabClip
        if (!clip || !clip.length) return
        if (model.length === 0) {
            model.push({ chords: [], events: [], bars: [] })
            curS = 0; curE = -1
        }
        var s = model[curS]
        var at = s.events.length ? selTo + 1 : 0
        var items = JSON.parse(JSON.stringify(clip))
        for (var i = 0; i < items.length; ++i) s.events.splice(at + i, 0, items[i])
        shift(s, at, items.length)
        selA = at
        curE = at + items.length - 1
        commit()
    }
    property int rev: 0

    function reload() {
        if (text === lastText) return
        model = text ? JSON.parse(Arara.CypherMusic.tabModel(text)) : []
        lastText = text
        clampCursor()
        rev++
    }
    onTextChanged: reload()
    Component.onCompleted: reload()

    function clampCursor() {
        if (model.length === 0) { curS = 0; curE = 0; return }
        curS = Math.max(0, Math.min(curS, model.length - 1))
        curE = Math.max(0, Math.min(curE, model[curS].events.length - 1))
    }
    function commit() {
        var t = Arara.CypherMusic.renderTab(JSON.stringify(model))
        lastText = t
        clampCursor()
        rev++
        edited(t)
    }
    function sys() { return model.length ? model[curS] : null }
    function ev() { var s = sys(); return s && s.events.length ? s.events[curE] : null }
    readonly property var current: rev, ev()
    // Cópia para a tela: o modelo é mexido no lugar e a Repeater só redesenha
    // quando recebe uma lista nova.
    readonly property var view: rev, JSON.parse(JSON.stringify(model))

    // Ajusta índices de acordes e barras quando um toque entra ou sai.
    function shift(s, from, d) {
        for (var i = 0; i < s.chords.length; ++i) if (s.chords[i].at >= from) s.chords[i].at += d
        for (var j = 0; j < s.bars.length; ++j) if (s.bars[j] >= from) s.bars[j] += d
        s.chords = s.chords.filter(function (c) { return c.at >= 0 && c.at < s.events.length })
        s.bars = s.bars.filter(function (b) { return b > 0 && b < s.events.length })
    }
    function ensure() {
        if (model.length === 0) model.push({ chords: [], events: [{ notes: [], arrow: "" }], bars: [] })
        if (model[curS].events.length === 0) model[curS].events.push({ notes: [], arrow: "" })
    }
    // ---- Teclado ----
    // Números digitam a casa na corda escolhida (dois seguidos = 10, 11...),
    // Delete/Backspace tira a nota, setas ←/→ andam nos toques e ↑/↓ nas
    // cordas, Insert ou "+" põe um toque depois, "-" exclui o toque.
    property string typed: ""
    Timer { id: typedTimer; interval: 900; onTriggered: root.typed = "" }
    function setNote(string, fret) {
        ensure()
        var e = model[curS].events[curE]
        e.notes = e.notes.filter(function (n) { return n.string !== string })
        if (fret >= 0) e.notes.push({ string: string, fret: fret })
        e.notes.sort(function (a, b) { return a.string - b.string })
        commit()
    }
    function step(d) {
        var s = sys()
        if (!s) return
        if (d > 0) {
            if (curE < s.events.length - 1) curE++
            else if (curS < model.length - 1) { curS++; curE = 0 }
        } else {
            if (curE > 0) curE--
            else if (curS > 0) { curS--; curE = model[curS].events.length - 1 }
        }
        typed = ""
        selA = -1
        rev++
    }
    focus: true
    Keys.onPressed: (e) => {
        var ctrl = e.modifiers & Qt.ControlModifier
        if (ctrl && e.key === Qt.Key_C) copySel()
        else if (ctrl && e.key === Qt.Key_X) cutSel()
        else if (ctrl && e.key === Qt.Key_V) paste()
        else if (ctrl && e.key === Qt.Key_A) { selA = 0; curE = sys() ? sys().events.length - 1 : 0; rev++ }
        else if ((e.modifiers & Qt.ShiftModifier) && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
            if (selA < 0) selA = curE
            var s2 = sys()
            if (s2) curE = Math.max(0, Math.min(s2.events.length - 1, curE + (e.key === Qt.Key_Right ? 1 : -1)))
            rev++
        }
        else if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9) {
            var d = String(e.key - Qt.Key_0)
            typed = typedTimer.running && typed.length === 1 && parseInt(typed + d) <= 24 ? typed + d : d
            typedTimer.restart()
            setNote(curString, Math.min(24, parseInt(typed)))
        } else if (e.key === Qt.Key_X) { typed = ""; setNote(curString, root.muted) }
        else if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) setNote(curString, -1)
        else if (e.key === Qt.Key_Left) step(-1)
        else if (e.key === Qt.Key_Right) step(1)
        else if (e.key === Qt.Key_Up) { curString = Math.min(5, curString + 1); typed = ""; rev++ }
        else if (e.key === Qt.Key_Down) { curString = Math.max(0, curString - 1); typed = ""; rev++ }
        else if (e.key === Qt.Key_Insert || e.key === Qt.Key_Plus) insert(true)
        else if (e.key === Qt.Key_Minus) remove()
        else return
        e.accepted = true
    }

    readonly property int muted: 255     // "x": corda abafada (tab::MUTED)
    function pick(string, fret) {
        ensure()
        var e = model[curS].events[curE]
        var had = e.notes.filter(function (n) { return n.string === string })
        e.notes = e.notes.filter(function (n) { return n.string !== string })
        if (!(had.length && had[0].fret === fret)) e.notes.push({ string: string, fret: fret })
        e.notes.sort(function (a, b) { return a.string - b.string })
        commit()
    }
    function insert(after) {
        ensure()
        var s = model[curS]
        var at = after ? curE + 1 : curE
        s.events.splice(at, 0, { notes: [], arrow: "" })
        shift(s, after ? at : at + 1, 1)
        if (!after) for (var i = 0; i < s.chords.length; ++i) if (s.chords[i].at === at + 1) s.chords[i].at = at
        curE = at
        commit()
    }
    function duplicate() {
        if (!ev()) return
        var s = model[curS]
        s.events.splice(curE + 1, 0, JSON.parse(JSON.stringify(s.events[curE])))
        shift(s, curE + 1, 1)
        curE++
        commit()
    }
    function remove() {
        var s = sys(); if (!s || !s.events.length) return
        s.events.splice(curE, 1)
        for (var i = 0; i < s.chords.length; ++i) if (s.chords[i].at === curE && curE >= s.events.length) s.chords[i].at = -1
        shift(s, curE + 1, -1)
        if (s.events.length === 0) { model.splice(curS, 1); curS = Math.max(0, curS - 1); curE = 0 }
        commit()
    }
    function cycleArrow(si, ei) {
        var e = model[si].events[ei]
        var order = ["", "D", "U", "D>", "U>", "X", "XU"]
        e.arrow = order[(order.indexOf(e.arrow) + 1) % order.length]
        commit()
    }
    // Seta do toque escolhido: "", D, U, X (↓ abafada), XU (↑ abafada).
    function setArrow(a) {
        if (!current) return
        model[curS].events[curE].arrow = a
        commit()
    }
    function toggleBar() {
        var s = sys(); if (!s || curE === 0) return
        var i = s.bars.indexOf(curE)
        if (i >= 0) s.bars.splice(i, 1); else s.bars.push(curE)
        commit()
    }
    function setChord(name) {
        ensure()
        var s = model[curS]
        s.chords = s.chords.filter(function (c) { return c.at !== curE })
        name = name.trim()
        if (name) s.chords.push({ at: curE, name: name })
        s.chords.sort(function (a, b) { return a.at - b.at })
        commit()
    }
    function newBlock() {
        model.push({ chords: [], events: [{ notes: [], arrow: "" }], bars: [] })
        curS = model.length - 1; curE = 0
        commit()
    }
    function moveNote(s1, e1, string1, s2, e2, string2) {
        var a = model[s1].events[e1]
        var n = a.notes.filter(function (x) { return x.string === string1 })[0]
        if (!n) return
        a.notes = a.notes.filter(function (x) { return x.string !== string1 })
        var b = model[s2].events[e2]
        b.notes = b.notes.filter(function (x) { return x.string !== string2 })
        b.notes.push({ string: string2, fret: n.fret, tech: n.tech || "" })
        b.notes.sort(function (p, q) { return p.string - q.string })
        curS = s2; curE = e2
        commit()
    }
    function moveEvent(s1, e1, s2, e2) {
        if (s1 !== s2 || e1 === e2) return
        var s = model[s1]
        var item = s.events.splice(e1, 1)[0]
        s.events.splice(e2, 0, item)
        curE = e2
        commit()
    }
    function chordAt(s, e) {
        for (var i = 0; i < s.chords.length; ++i) if (s.chords[i].at === e) return s.chords[i].name
        return ""
    }

    readonly property real colW: 34
    readonly property real rowH: 22
    readonly property real labelW: 26
    readonly property real sysH: rowH * 8 + 8
    function colX(s, e) {
        var x = labelW
        for (var i = 1; i <= e; ++i) x += colW + (model[s].bars.indexOf(i) >= 0 ? 8 : 0)
        return x
    }

    spacing: 10

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Toque numa corda de um toque e digite a casa (dois números seguidos = 10, 11...). X = corda abafada (não tocar), Delete tira, setas ←→ andam nos toques e ↑↓ nas cordas, + põe um toque depois, − exclui. Arraste uma nota para outra corda ou toque; arraste o topo da coluna para mudar o toque de lugar. Toque embaixo para pôr a seta.\nCopiar e colar: Shift+clique (ou Shift+setas) escolhe vários toques; Ctrl+C copia, Ctrl+X recorta, Ctrl+V cola depois do toque escolhido (vale de uma parte para outra)."
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    // ---- Todos os toques ----
    Flickable {
        id: flick
        width: parent.width
        height: Math.max(root.sysH, strip.height) + (contentWidth > width ? 16 : 0)
        contentWidth: strip.width
        // Barra de rolagem horizontal quando os toques passam da largura.
        ScrollBar.horizontal: AppScrollBar {}
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: !drag.active
        clip: true

        Item {
            id: strip
            width: Math.max(flick.width, root.rev, root.model.reduce(function (w, s, i) {
                return Math.max(w, root.colX(i, s.events.length) + 20) }, 0))
            height: Math.max(1, root.model.length) * (root.sysH + 10)

            Repeater {
                model: root.view
                Item {
                    id: sysItem
                    required property var modelData
                    required property int index
                    y: index * (root.sysH + 10)
                    width: strip.width
                    height: root.sysH

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: Theme.dark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, 0.04)
                    }
                    // Cordas.
                    Repeater {
                        model: 6
                        Item {
                            required property int index
                            y: root.rowH * (index + 1)
                            width: parent.width
                            height: root.rowH
                            Text {
                                width: root.labelW
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: ["e", "B", "G", "D", "A", "E"][parent.index]
                                color: Theme.chord
                                font.family: Theme.monoFamily
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Rectangle {
                                x: root.labelW
                                width: root.colX(sysItem.index, sysItem.modelData.events.length) - x + 4
                                // Posição inteira e 2 px: com escala de tela fracionária uma
                                // linha de 1 px no meio de um pixel sumia (faltava a corda Lá).
                                y: Math.round(parent.height / 2) - 1
                                height: 2
                                color: Theme.textDim
                                opacity: 0.45
                            }
                        }
                    }
                    // Toques.
                    Repeater {
                        model: sysItem.modelData.events
                        Item {
                            id: col
                            required property var modelData
                            required property int index
                            readonly property bool selected: sysItem.index === root.curS && index === root.curE
                            readonly property bool inRange: root.rev, sysItem.index === root.curS && index >= root.selFrom && index <= root.selTo
                            x: root.colX(sysItem.index, index)
                            width: root.colW
                            height: root.sysH
                            Rectangle {
                                visible: sysItem.modelData.bars.indexOf(col.index) >= 0
                                x: -5
                                y: root.rowH * 1.5
                                width: 1.5
                                height: root.rowH * 5
                                color: Theme.text
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 4
                                color: col.inRange ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, col.selected ? 0.3 : 0.16) : "transparent"
                                border.width: col.selected ? 1.5 : 0
                                border.color: Theme.accent
                            }
                            // Casa onde o teclado escreve.
                            Rectangle {
                                visible: col.selected
                                x: 2
                                y: root.rowH * (6 - root.curString) + 1
                                width: parent.width - 4
                                height: root.rowH - 2
                                radius: 4
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.chord
                            }
                            Text {
                                x: 2
                                y: 3
                                text: root.chordAt(sysItem.modelData, col.index)
                                color: Theme.chord
                                font.family: Theme.monoFamily
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Repeater {
                                model: col.modelData.notes
                                Rectangle {
                                    required property var modelData
                                    // Corda solta junto de outras notas: um anel pequeno, sem número
                                    // (menos poluído). Sozinha no toque, fica o 0.
                                    readonly property bool open: modelData.fret === 0 && !modelData.tech && col.modelData.notes.length > 1
                                    readonly property color ink: Theme.fretColor(modelData.fret)
                                    y: root.rowH * (6 - modelData.string) + (open ? (root.rowH - height) / 2 : 2)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: open ? 11 : Math.max(20, t.implicitWidth + 6)
                                    height: open ? 11 : root.rowH - 4
                                    radius: height / 2
                                    color: open ? Theme.card : Qt.rgba(ink.r, ink.g, ink.b, 0.14)
                                    border.width: open ? 2 : 1.4
                                    border.color: open ? Theme.textDim : ink
                                    Text {
                                        id: t
                                        visible: !parent.open
                                        anchors.centerIn: parent
                                        text: (parent.modelData.tech || "") + (parent.modelData.fret === root.muted ? "x" : parent.modelData.fret)
                                        color: parent.ink
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: root.rowH * 7 + 1
                                text: col.modelData.arrow ? Examples.strokeArrow(col.modelData.arrow) : "·"
                                color: col.modelData.arrow ? Theme.chord : Theme.textDim
                                font.pixelSize: 17
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // Um ponto só para tocar e arrastar (escolher, mover nota, mover toque, seta).
            Rectangle {
                id: ghost
                visible: drag.active
                width: 26; height: 20; radius: 10
                color: Theme.accent
                opacity: 0.8
                Text { anchors.centerIn: parent; text: drag.label; color: Theme.accentFg; font.bold: true; font.pixelSize: 12 }
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                preventStealing: active
                cursorShape: active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property var from: null
                property bool active: false
                property string label: ""
                property real px: 0
                property real py: 0
                function hit(x, y) {
                    var s = Math.floor(y / (root.sysH + 10))
                    if (s < 0 || s >= root.model.length) return null
                    var ly = y - s * (root.sysH + 10)
                    var row = Math.floor(ly / root.rowH)
                    var evs = root.model[s].events
                    var e = -1
                    for (var i = 0; i < evs.length; ++i) {
                        var cx = root.colX(s, i)
                        if (x >= cx - 4 && x < cx + root.colW + 4) { e = i; break }
                    }
                    if (e < 0) return null
                    return { s: s, e: e, row: row, string: row >= 1 && row <= 6 ? 6 - row : -1 }
                }
                onPressed: (m) => {
                    from = hit(m.x, m.y); active = false; px = m.x; py = m.y
                    if (!from) return
                    var e = root.model[from.s].events[from.e]
                    var n = from.string >= 0 ? e.notes.filter(function (x) { return x.string === from.string })[0] : null
                    from.note = !!n
                    label = n ? String(n.fret) : "↔"
                }
                onPositionChanged: (m) => {
                    if (!from) return
                    if (!active && Math.abs(m.x - px) + Math.abs(m.y - py) > 8) active = true
                    ghost.x = m.x - ghost.width / 2; ghost.y = m.y - ghost.height / 2
                }
                onReleased: (m) => {
                    var to = hit(m.x, m.y)
                    var f = from, wasDrag = active
                    active = false; from = null
                    if (!f) return
                    if (!wasDrag) {
                        root.forceActiveFocus()
                        if ((m.modifiers & Qt.ShiftModifier) && f.s === root.curS) {
                            if (root.selA < 0) root.selA = root.curE
                        } else root.selA = -1
                        root.curS = f.s; root.curE = f.e
                        if (f.string >= 0) root.curString = f.string
                        root.typed = ""
                        root.rev++
                        if (f.row >= 7) root.cycleArrow(f.s, f.e)
                        return
                    }
                    if (!to) return
                    if (f.note && to.string >= 0) root.moveNote(f.s, f.e, f.string, to.s, to.e, to.string)
                    else if (!f.note) root.moveEvent(f.s, f.e, to.s, to.e)
                }
                onCanceled: { active = false; from = null }
            }
        }
    }

    // ---- Ações no toque escolhido ----
    Flow {
        width: parent.width
        spacing: 6
        AppButton { text: "◀"; onClicked: { if (root.curE > 0) root.curE--; else if (root.curS > 0) { root.curS--; root.curE = root.model[root.curS].events.length - 1 } root.rev++ } }
        AppButton { text: "▶"; onClicked: { var s = root.sys(); if (s && root.curE < s.events.length - 1) root.curE++; else if (root.curS < root.model.length - 1) { root.curS++; root.curE = 0 } root.rev++ } }
        AppButton { text: "Toque antes"; iconName: "add"; onClicked: root.insert(false) }
        AppButton { text: "Toque depois"; iconName: "add"; onClicked: root.insert(true) }
        AppButton { text: "x (não tocar)"; enabled: !!root.current; onClicked: { root.forceActiveFocus(); root.setNote(root.curString, root.muted) } }
        AppButton { text: "Duplicar"; enabled: !!root.current; onClicked: root.duplicate() }
        AppButton { text: "Excluir toque"; enabled: !!root.current; onClicked: root.remove() }
        // Seta do toque: escolhe direto (abafada = ↓× / ↑×).
        Row {
            spacing: 4
            Text {
                height: Theme.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: "Seta:"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
            Repeater {
                model: [{ code: "", label: "nenhuma" }, { code: "D", label: "↓" }, { code: "U", label: "↑" },
                        { code: "D>", label: "⬇ forte" }, { code: "U>", label: "⬆ forte" },
                        { code: "X", label: "↓× abafada" }, { code: "XU", label: "↑× abafada" }]
                AppButton {
                    required property var modelData
                    enabled: !!root.current
                    text: modelData.label
                    suggested: root.rev, !!root.current && root.current.arrow === modelData.code
                    onClicked: { root.forceActiveFocus(); root.setArrow(modelData.code) }
                }
            }
        }
        AppButton {
            enabled: !!root.current && root.curE > 0
            text: root.rev, root.sys() && root.sys().bars.indexOf(root.curE) >= 0 ? "Tirar barra" : "Barra antes"
            onClicked: root.toggleBar()
        }
        AppButton { text: root.selCount > 1 ? "Copiar " + root.selCount + " toques" : "Copiar"; enabled: !!root.current; onClicked: root.copySel() }
        AppButton { text: "Recortar"; enabled: !!root.current; onClicked: root.cutSel() }
        AppButton {
            text: root.rev, Examples.tabClip.length > 1 ? "Colar " + Examples.tabClip.length + " toques" : "Colar"
            enabled: root.rev, Examples.tabClip.length > 0
            onClicked: root.paste()
        }
        AppButton { text: "Novo bloco"; flat: true; onClicked: root.newBlock() }
    }
    RowLayout {
        width: parent.width
        spacing: 6
        Text {
            text: "Acorde neste toque"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        AppTextField {
            id: chordField
            Layout.preferredWidth: 120
            mono: true
            placeholderText: "ex.: Am"
            text: root.rev, root.sys() ? root.chordAt(root.sys(), root.curE) : ""
            onEditingFinished: if (text.trim() !== (root.sys() ? root.chordAt(root.sys(), root.curE) : "")) root.setChord(text)
        }
        Item { Layout.fillWidth: true }
    }
}
