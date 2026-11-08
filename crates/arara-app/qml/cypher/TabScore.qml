import QtQuick
import AraraCypher
import io.github.arara as Arara

// Riff ou solo em partitura + tablatura, a partir de uma tab em texto.
// As notas vêm do leitor de tab do núcleo (Arara.CypherMusic.parseTab): cada coluna da
// tab vira uma nota (ou notas juntas), escrita como colcheia, já que a tab em
// texto não diz o ritmo. Barras "|" da tab viram barras de compasso.
// Quebra em várias linhas para caber na largura.
Canvas {
    id: root
    property string tab
    property string keyName: "C"       // tom, para escrever ♯ ou ♭
    property real zoom: 1
    property int startNumber: 0        // número do compasso (0 = não mostra)
    property string label: ""          // nome da parte, em cima da primeira linha
    property bool editing: false       // tocar embaixo da nota põe/troca a seta
    property bool showChords: false    // escreve em cima o acorde marcado na tab
    property int semitones: 0
    property bool showStaff: true      // false: só a tab (sem a pauta)
    onShowStaffChanged: requestPaint()
    onShowChordsChanged: requestPaint()
    // Acordes marcados na tab (linha de acordes em cima), por bloco e toque.
    readonly property var marks: {
        if (!showChords || tab.length === 0) return []
        var m = JSON.parse(Arara.CypherMusic.tabModel(tab))
        return m.map(function (sys) { return sys.chords || [] })
    }
    function markAt(s, e) {
        var cs = marks[s] || []
        for (var i = 0; i < cs.length; ++i) if (cs[i].at === e) return cs[i].name
        return ""
    }
    signal arrowClicked(int system, int event, string arrow)

    // Eventos em ordem (notas e barras), com a seta da batida de cada nota
    // quando a tab traz a linha de setas embaixo.
    readonly property var events: {
        if (tab.length === 0) return []
        var systems = JSON.parse(Arara.CypherMusic.lessonTab(tab))
        var out = [], seg = 0
        for (var s = 0; s < systems.length; ++s) {
            var sys = systems[s]
            if (s > 0) { out.push({ bar: true }); seg++ }
            var bi = 0
            for (var e = 0; e < sys.events.length; ++e) {
                while (bi < sys.bars.length && sys.bars[bi] < sys.events[e].col) {
                    if (out.length && !out[out.length - 1].bar) { out.push({ bar: true }); seg++ }
                    bi++
                }
                out.push({ notes: sys.events[e].notes, arrow: sys.events[e].arrow || "", s: s, e: e, seg: seg })
            }
        }
        while (out.length && out[out.length - 1].bar) out.pop()
        return out
    }
    readonly property bool hasArrows: events.some(function (e) { return !!e.arrow })
    readonly property real lw: width / zoom

    readonly property real gap: 9
    readonly property real tabGap: 11
    readonly property real clefW: 48
    property real slotW: 24            // largura de cada toque (menor para caber num quadro)
    onSlotWChanged: requestPaint()
    readonly property real barW: 12
    // Nota mais aguda da tab (passo diatônico), para dar espaço às notas e
    // hastes que passam por cima da pauta.
    readonly property int maxStep: {
        var open = [40, 45, 50, 55, 59, 64], top = 38
        for (var i = 0; i < events.length; ++i) {
            var ns = events[i].notes || []
            for (var k = 0; k < ns.length; ++k)
                if (ns[k].fret !== 255) top = Math.max(top, Examples.spell(open[ns[k].string] + ns[k].fret, keyName).step)
        }
        return top
    }
    // Espaço em cima: a nota mais alta acima da linha de cima, a haste
    // (3,5 espaços) e a barra da colcheia.
    readonly property real headroom: !showStaff ? 6 : Math.max(18, (maxStep - 38) * gap / 2 + gap * 3.5 + 8)
    readonly property real topPad: (label.length > 0 ? 14 : 0) + (marks.some(function (c) { return c.length > 0 }) ? 16 : 0) + headroom
    readonly property real staffH: showStaff ? gap * 4 : 0
    readonly property real staffGap: showStaff ? gap * 6 : 0
    readonly property real rowH: topPad + staffH + staffGap + tabGap * 5 + 22 + (hasArrows || editing ? 20 : 0)

    // Divide os eventos em linhas que cabem na largura.
    readonly property var rows: {
        var out = []
        var avail = Math.max(120, lw - clefW - 8)
        var cur = [], used = 0
        for (var i = 0; i < events.length; ++i) {
            var w = events[i].bar ? barW : slotW
            if (used + w > avail && cur.length > 0) {
                out.push(cur); cur = []; used = 0
                if (events[i].bar) continue
            }
            cur.push(events[i]); used += w
        }
        if (cur.length > 0) out.push(cur)
        return out
    }

    implicitHeight: Math.max(1, rows.length) * rowH * zoom
    visible: events.length > 0

    onRowsChanged: requestPaint()
    onZoomChanged: requestPaint()
    onEditingChanged: requestPaint()
    onKeyNameChanged: requestPaint()
    Connections {
        target: Theme
        function onDarkChanged() { root.requestPaint() }
        function onStyleChanged() { root.requestPaint() }
        function onSlashChordsChanged() { root.requestPaint() }
    }

    function drawClef(ctx, color, x, staffTop) {
        var staffBottom = staffTop + staffH
        var yOf = function (step) { return staffBottom - (step - 30) * gap / 2 }
        var top = staffTop - gap * 1.6, bottom = staffBottom + gap * 1.8
        ctx.strokeStyle = color
        ctx.lineWidth = 1.8
        ctx.beginPath()
        ctx.moveTo(x + 2, bottom)
        ctx.bezierCurveTo(x + 4, bottom - gap, x + 4, top + gap * 2, x + 6, top + gap * 0.6)
        ctx.bezierCurveTo(x + 8, top - gap * 0.4, x + 1, top - gap * 0.2, x + 1, top + gap * 1.6)
        ctx.bezierCurveTo(x + 1, top + gap * 3, x + 11, yOf(32) - gap * 0.5, x + 10, yOf(32) + gap * 1.2)
        ctx.bezierCurveTo(x + 9, staffBottom + gap * 0.3, x - 5, staffBottom, x - 4, yOf(32))
        ctx.bezierCurveTo(x - 3, yOf(34) - gap * 0.2, x + 7, yOf(34), x + 7, yOf(32))
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(x, bottom - 1, 2.2, 0, Math.PI * 2)
        ctx.fillStyle = color
        ctx.fill()
        ctx.font = "bold 9px sans-serif"
        ctx.fillText("8", x - 1, bottom + 11)
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (events.length === 0) return
        ctx.scale(zoom, zoom)
        var ink = Theme.text, dim = Theme.textDim, accent = Theme.accent
        var open = [40, 45, 50, 55, 59, 64]
        var measure = startNumber

        for (var r = 0; r < rows.length; ++r) {
            var row = rows[r]
            var y0 = r * rowH
            var staffTop = y0 + topPad
            var staffBottom = staffTop + staffH
            var tabTop = staffBottom + staffGap
            var tabBottom = tabTop + tabGap * 5
            var yOf = function (step) { return staffBottom - (step - 30) * gap / 2 }
            // A última linha termina logo depois da última nota.
            var rowEnd = lw - 1
            if (r === rows.length - 1) {
                var used = clefW + 8
                for (var u = 0; u < row.length; ++u) used += row[u].bar ? barW : slotW
                rowEnd = Math.min(lw - 1, used)
            }

            if (r === 0 && label.length > 0) {
                ctx.fillStyle = accent
                ctx.font = "bold 11px sans-serif"
                ctx.fillText(label.toUpperCase(), clefW, y0 + 12)
            }
            if (measure > 0 && showStaff) {
                ctx.fillStyle = dim
                ctx.font = "11px sans-serif"
                ctx.fillText(String(measure), 14, staffTop - gap * 1.4)
            }

            // Chave, linhas, clave e letras da tab.
            ctx.strokeStyle = ink
            ctx.lineWidth = 2
            if (showStaff) {
                ctx.beginPath()
                ctx.moveTo(8, staffTop)
                ctx.bezierCurveTo(2, staffTop + 10, 8, (staffTop + tabBottom) / 2 - 10, 3, (staffTop + tabBottom) / 2)
                ctx.bezierCurveTo(8, (staffTop + tabBottom) / 2 + 10, 2, tabBottom - 10, 8, tabBottom)
                ctx.stroke()
            }
            ctx.strokeStyle = dim
            ctx.lineWidth = 1
            for (var l = 0; showStaff && l < 5; ++l) {
                var ly = Math.round(staffTop + l * gap) + 0.5
                ctx.beginPath(); ctx.moveTo(12, ly); ctx.lineTo(rowEnd, ly); ctx.stroke()
            }
            for (var t = 0; t < 6; ++t) {
                var ty = Math.round(tabTop + t * tabGap) + 0.5
                ctx.beginPath(); ctx.moveTo(12, ty); ctx.lineTo(rowEnd, ty); ctx.stroke()
            }
            ctx.beginPath(); ctx.moveTo(12.5, staffTop); ctx.lineTo(12.5, tabBottom); ctx.stroke()
            if (showStaff) { ctx.beginPath(); ctx.moveTo(rowEnd - 0.5, staffTop); ctx.lineTo(rowEnd - 0.5, staffBottom); ctx.stroke() }
            ctx.beginPath(); ctx.moveTo(rowEnd - 0.5, tabTop); ctx.lineTo(rowEnd - 0.5, tabBottom); ctx.stroke()
            if (showStaff) drawClef(ctx, ink, 22, staffTop)
            // Nome de cada corda no começo da linha dela (e em cima, E embaixo).
            ctx.font = "bold 10px monospace"
            var names = ["e", "B", "G", "D", "A", "E"]
            for (var sn = 0; sn < 6; ++sn) {
                var ny = Math.round(tabTop + sn * tabGap)
                var nw = ctx.measureText(names[sn]).width
                ctx.fillStyle = Theme.card
                ctx.fillRect(30 - 2, ny - 5, nw + 4, 10)
                ctx.fillStyle = Theme.chord
                ctx.fillText(names[sn], 30, ny + 4)
            }

            var x = clefW
            var stems = []
            // Última nota de cada corda nesta linha (na tab e na pauta), para
            // ligar o slide "8/10" com uma linha diagonal.
            var lastTab = {}, lastHead = {}
            for (var i = 0; i < row.length; ++i) {
                var ev = row[i]
                if (ev.bar) {
                    var bx = Math.round(x + barW / 2) + 0.5
                    ctx.strokeStyle = ink
                    ctx.lineWidth = 1
                    if (showStaff) { ctx.beginPath(); ctx.moveTo(bx, staffTop); ctx.lineTo(bx, staffBottom); ctx.stroke() }
                    ctx.beginPath(); ctx.moveTo(bx, tabTop); ctx.lineTo(bx, tabBottom); ctx.stroke()
                    stems.push(null)
                    x += barW
                    if (measure > 0) measure++
                    continue
                }
                var cx = x + slotW / 2
                // Nome do acorde marcado na tab em cima deste toque.
                var mark = showChords ? markAt(ev.s, ev.e) : ""
                if (mark) {
                    ctx.fillStyle = Theme.chord
                    ctx.font = "bold 13px monospace"
                    ctx.fillText(Arara.CypherMusic.transposeChord(Examples.chordName(mark), semitones), cx - 6, y0 + (label.length > 0 ? 28 : 13))
                }
                // Tab.
                ctx.font = "bold 11px sans-serif"
                for (var k = 0; k < ev.notes.length; ++k) {
                    var n = ev.notes[k]
                    var label2 = n.fret === 255 ? "x" : String(n.fret)
                    var tyy = tabTop + (5 - n.string) * tabGap
                    var tw = ctx.measureText(label2).width
                    ctx.fillStyle = Theme.card
                    ctx.fillRect(cx - tw / 2 - 2, tyy - 6, tw + 4, 12)
                    if (n.fret === 0 && !n.tech && ev.notes.length > 1) {
                        // Corda solta junto de outras notas: anel pequeno em vez do 0
                        // (menos poluído). Sozinha no toque, fica o 0.
                        ctx.strokeStyle = dim
                        ctx.lineWidth = 1.6
                        ctx.beginPath(); ctx.arc(cx, tyy, 3.6, 0, 2 * Math.PI); ctx.stroke()
                    } else {
                        ctx.fillStyle = Theme.fretColor(n.fret)
                        ctx.fillText(label2, cx - tw / 2, tyy + 4)
                    }
                    var slideT = n.tech === "/" || n.tech === "\\"
                    if (slideT) {
                        // Slide: linha diagonal da nota anterior da corda até esta,
                        // subindo (/) ou descendo (\\). Sem nota antes, entra de fora.
                        var up = n.tech === "/"
                        var pv = lastTab[n.string]
                        var x1 = pv ? pv.x + pv.w / 2 + 2 : cx - slotW / 2 - 4
                        var x2 = cx - tw / 2 - 2
                        if (x2 - x1 < 6) x1 = x2 - 6
                        ctx.strokeStyle = accent
                        ctx.lineWidth = 1.8
                        ctx.beginPath()
                        ctx.moveTo(x1, tyy + (up ? 4 : -4))
                        ctx.lineTo(x2, tyy + (up ? -4 : 4))
                        ctx.stroke()
                        if (!pv || cx - pv.x > slotW * 1.5) {
                            ctx.fillStyle = accent
                            ctx.font = "9px sans-serif"
                            ctx.fillText("sl.", (x1 + x2) / 2 - 6, tyy - 7)
                        }
                        ctx.font = "bold 11px sans-serif"
                    } else if (n.tech) {
                        ctx.fillStyle = accent
                        ctx.font = "10px sans-serif"
                        ctx.fillText(n.tech.toUpperCase(), cx - slotW / 2 - 2, tyy - 6)
                        ctx.font = "bold 11px sans-serif"
                    }
                    if (n.fret !== 255) lastTab[n.string] = { x: cx, w: tw }
                    else delete lastTab[n.string]
                }
                // Direção da palhetada embaixo da tab.
                if (editing) {
                    ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.45)
                    ctx.lineWidth = 1
                    ctx.strokeRect(cx - slotW / 2 + 2.5, tabBottom + 6.5, slotW - 5, 21)
                    if (!ev.arrow) {
                        ctx.fillStyle = dim
                        ctx.font = "bold 13px sans-serif"
                        ctx.fillText("·", cx - ctx.measureText("·").width / 2, tabBottom + 21)
                    }
                }
                if (ev.arrow) {
                    ctx.fillStyle = accent
                    ctx.font = "bold 15px sans-serif"
                    var strongA = Examples.isAccent(ev.arrow), baseA = Examples.plain(ev.arrow)
                    var ar = baseA === "U" || baseA === "XU" ? (strongA ? "⬆" : "↑") : (strongA ? "⬇" : "↓")
                    if (strongA) ctx.font = "900 19px sans-serif"
                    ctx.fillText(ar, cx - ctx.measureText(ar).width / 2, tabBottom + 22)
                    if (strongA) {
                        // Acento ">" em cima da tab, como na partitura.
                        ctx.font = "bold 12px sans-serif"
                        ctx.fillText(">", cx - ctx.measureText(">").width / 2, tabTop - 6)
                    }
                    if (baseA === "X" || baseA === "XU") {
                        // Batida abafada: × junto da seta.
                        ctx.fillStyle = Theme.destructive
                        ctx.font = "bold 13px sans-serif"
                        ctx.fillText("×", cx + 3, tabBottom + 15)
                    }
                    ctx.font = "bold 11px sans-serif"
                }
                // Pauta.
                if (!showStaff) { stems.push(null); x += slotW; continue }
                var sounding = ev.notes.filter(function (q) { return q.fret !== 255 })
                if (Theme.slashChords && ev.notes.length >= 3) {
                    // Batida de acorde: barra de ritmo na linha do meio (o acorde
                    // está escrito em cima; as notas estão na tab). Abafada = x.
                    var my = staffTop + gap * 2
                    ctx.strokeStyle = accent
                    ctx.fillStyle = accent
                    if (sounding.length === 0) {
                        ctx.lineWidth = 2
                        ctx.beginPath(); ctx.moveTo(cx - 4, my - 4); ctx.lineTo(cx + 4, my + 4)
                        ctx.moveTo(cx + 4, my - 4); ctx.lineTo(cx - 4, my + 4); ctx.stroke()
                    } else {
                        ctx.beginPath()
                        ctx.moveTo(cx - 5, my + 3); ctx.lineTo(cx - 1, my + 5)
                        ctx.lineTo(cx + 5, my - 3); ctx.lineTo(cx + 1, my - 5)
                        ctx.closePath(); ctx.fill()
                    }
                    var sTop2 = my - gap * 3.5
                    ctx.strokeStyle = ink
                    ctx.lineWidth = 1.2
                    ctx.beginPath(); ctx.moveTo(cx + 4.5, my - 2); ctx.lineTo(cx + 4.5, sTop2); ctx.stroke()
                    stems.push({ x: cx + 4.5, y: sTop2 })
                    x += slotW
                    continue
                }
                var minY = 1e9, maxY = -1e9, prevStep = -100
                for (var m = 0; m < ev.notes.length; ++m) {
                    var note = ev.notes[m]
                    if (note.fret === 255) continue   // abafada: só na tab
                    var sp = Examples.spell(open[note.string] + note.fret, keyName)
                    var y = yOf(sp.step)
                    minY = Math.min(minY, y); maxY = Math.max(maxY, y)
                    ctx.strokeStyle = dim
                    ctx.lineWidth = 1
                    for (var st = 28; st >= sp.step; st -= 2) {
                        var l1 = Math.round(yOf(st)) + 0.5
                        ctx.beginPath(); ctx.moveTo(cx - 7, l1); ctx.lineTo(cx + 7, l1); ctx.stroke()
                    }
                    for (var st2 = 40; st2 <= sp.step; st2 += 2) {
                        var l2 = Math.round(yOf(st2)) + 0.5
                        ctx.beginPath(); ctx.moveTo(cx - 7, l2); ctx.lineTo(cx + 7, l2); ctx.stroke()
                    }
                    var nx = (sp.step - prevStep === 1) ? cx + 6 : cx
                    prevStep = sp.step
                    if (note.tech === "/" || note.tech === "\\") {
                        // Slide na pauta: linha reta de uma cabeça de nota à outra.
                        var ph = lastHead[note.string]
                        ctx.strokeStyle = accent
                        ctx.lineWidth = 1.6
                        ctx.beginPath()
                        if (ph) { ctx.moveTo(ph.x + 7, ph.y); ctx.lineTo(nx - 8, y) }
                        else { ctx.moveTo(nx - 18, y + (note.tech === "/" ? 6 : -6)); ctx.lineTo(nx - 8, y) }
                        ctx.stroke()
                    }
                    lastHead[note.string] = { x: nx, y: y }
                    ctx.fillStyle = accent
                    ctx.save()
                    ctx.translate(nx, y); ctx.rotate(-0.35); ctx.scale(1.35, 1)
                    ctx.beginPath(); ctx.arc(0, 0, gap / 2 - 0.3, 0, Math.PI * 2); ctx.fill()
                    ctx.restore()
                    if (sp.acc !== 0) {
                        ctx.fillStyle = ink
                        ctx.font = "13px sans-serif"
                        ctx.fillText(sp.acc > 0 ? "♯" : "♭", cx - 15, y + 5)
                    }
                }
                if (minY > maxY) { stems.push(null); x += slotW; continue }   // só cordas abafadas: nada na pauta
                var stTop = minY - gap * 3.5
                ctx.strokeStyle = ink
                ctx.lineWidth = 1.2
                ctx.beginPath(); ctx.moveTo(cx + 4.5, maxY); ctx.lineTo(cx + 4.5, stTop); ctx.stroke()
                stems.push({ x: cx + 4.5, y: stTop })
                x += slotW
            }

            // Colcheias em pares (sem atravessar barra de compasso).
            ctx.strokeStyle = ink
            ctx.fillStyle = ink
            var p = 0
            while (p < stems.length) {
                var a = stems[p], b = p + 1 < stems.length ? stems[p + 1] : null
                if (a && b) {
                    var yb = Math.min(a.y, b.y)
                    ctx.fillRect(a.x - 0.6, yb, b.x - a.x + 1.2, 3.5)
                    ctx.lineWidth = 1.2
                    ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(a.x, yb); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(b.x, b.y); ctx.lineTo(b.x, yb); ctx.stroke()
                    p += 2
                } else {
                    if (a) {
                        ctx.lineWidth = 1.6
                        ctx.beginPath()
                        ctx.moveTo(a.x, a.y)
                        ctx.bezierCurveTo(a.x + 2, a.y + 5, a.x + 9, a.y + 7, a.x + 6, a.y + 14)
                        ctx.stroke()
                    }
                    p += 1
                }
            }
        }
    }

    // Modo de edição: o toque embaixo de uma nota troca a seta (nada → ↓ → ↑ → nada).
    MouseArea {
        anchors.fill: parent
        enabled: root.editing
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => {
            var lx = m.x / root.zoom, ly = m.y / root.zoom
            var r = Math.floor(ly / root.rowH)
            if (r < 0 || r >= root.rows.length) return
            var x = root.clefW
            var row = root.rows[r]
            for (var i = 0; i < row.length; ++i) {
                var w = row[i].bar ? root.barW : root.slotW
                if (lx >= x && lx < x + w && !row[i].bar) {
                    var order = ["", "D", "U", "D>", "U>", "X", "XU"]
                    var next = order[(order.indexOf(row[i].arrow) + 1) % order.length]
                    root.arrowClicked(row[i].s, row[i].e, next)
                    return
                }
                x += w
            }
        }
    }
}
