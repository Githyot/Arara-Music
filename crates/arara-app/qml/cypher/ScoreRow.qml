import QtQuick
import AraraCypher
import io.github.arara as Arara

// Uma linha da partitura completa: pauta (clave de sol com 8) em cima e tab
// de seis linhas embaixo, ligadas por uma chave, com vários compassos lado a
// lado. Cada compasso é um acorde tocado com a batida da música; o número do
// primeiro compasso fica no começo da linha, o nome do acorde em cima e o nome
// da parte (Intro, Refrão...) e as repetições quando a parte começa ou termina.
Canvas {
    id: root
    property var measures: []      // [{ chord, number, label, repeat }]
    property var pattern: []
    property int semitones: 0
    property real zoom: 1
    property int slots: 0            // compassos que cabem na linha (linhas incompletas não esticam)            // tamanho escolhido na tela da música
    readonly property real lw: width / zoom   // largura lógica do desenho

    readonly property real gap: 9
    readonly property real tabGap: 11
    readonly property real clefW: 48
    // Espaço em cima: cabe a nota mais aguda dos acordes da linha com a haste.
    readonly property int maxStep: {
        var open = [40, 45, 50, 55, 59, 64], top = 38
        for (var i = 0; i < measures.length; ++i) {
            var sh = Examples.shape(measures[i].chord, semitones, measures[i].voicing || null)
            if (!sh) continue
            for (var k = 0; k < 6; ++k)
                if (sh.frets[k] >= 0)
                    top = Math.max(top, Examples.spell(open[k] + sh.frets[k], measures[i].chord).step)
        }
        return top
    }
    readonly property real topPad: Math.max(46, (maxStep - 38) * gap / 2 + gap * 3.5 + 26)
    readonly property real staffTop: topPad
    readonly property real staffBottom: staffTop + gap * 4
    readonly property real tabTop: staffBottom + gap * 6
    readonly property real tabBottom: tabTop + tabGap * 5

    implicitHeight: (tabBottom + 14) * zoom

    onMeasuresChanged: requestPaint()
    onSemitonesChanged: requestPaint()
    onZoomChanged: requestPaint()
    onSlotsChanged: requestPaint()
    onPatternChanged: requestPaint()
    onWidthChanged: requestPaint()
    Connections {
        target: Theme
        function onDarkChanged() { root.requestPaint() }
        function onStyleChanged() { root.requestPaint() }
    }

    function shapeOf(chord, voicing) {
        return Examples.shape(chord, semitones, voicing || null)
    }

    // Cordas tocadas em cada tempo (mesmas regras do StrumTab).
    function eventsOf(shape, pattern) {
        var out = []
        if (!shape) return out
        var played = []
        for (var s = 0; s < 6; ++s)
            if (shape.frets[s] >= 0) played.push(s)
        var upper = played.filter(function (s) { return s > shape.root })
        var top3 = played.slice(-3)
        for (var i = 0; i < pattern.length; ++i) {
            var code = pattern[i]
            out.push({
                code: code,
                strings: Examples.strokeStrings(shape, code)
            })
        }
        return out
    }

    function yOf(step) { return staffBottom - (step - 30) * gap / 2 }

    function drawClef(ctx, color) {
        var x = 20, t = staffTop - gap * 1.6, b = staffBottom + gap * 1.8
        ctx.strokeStyle = color
        ctx.lineWidth = 1.8
        ctx.beginPath()
        ctx.moveTo(x + 2, b)
        ctx.bezierCurveTo(x + 4, b - gap, x + 4, t + gap * 2, x + 6, t + gap * 0.6)
        ctx.bezierCurveTo(x + 8, t - gap * 0.4, x + 1, t - gap * 0.2, x + 1, t + gap * 1.6)
        ctx.bezierCurveTo(x + 1, t + gap * 3, x + 11, yOf(32) - gap * 0.5, x + 10, yOf(32) + gap * 1.2)
        ctx.bezierCurveTo(x + 9, staffBottom + gap * 0.3, x - 5, staffBottom, x - 4, yOf(32))
        ctx.bezierCurveTo(x - 3, yOf(34) - gap * 0.2, x + 7, yOf(34), x + 7, yOf(32))
        ctx.stroke()
        ctx.fillStyle = color
        ctx.beginPath(); ctx.arc(x, b - 1, 2.2, 0, Math.PI * 2); ctx.fill()
        ctx.font = "bold 9px sans-serif"
        ctx.fillText("8", x - 1, b + 11)
        // "TAB" na tab.
        ctx.font = "bold 11px sans-serif"
        ctx.fillText("T", x - 2, tabTop + tabGap * 1.4)
        ctx.fillText("A", x - 2, tabTop + tabGap * 2.7)
        ctx.fillText("B", x - 2, tabTop + tabGap * 4.0)
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (measures.length === 0) return
        ctx.scale(zoom, zoom)
        var ink = Theme.text, dim = Theme.textDim, accent = Theme.accent, chordColor = Theme.chord
        var count = measures.length
        var mW = (lw - clefW - 2) / Math.max(count, slots)
        var lineEnd = Math.min(lw - 1, clefW + count * mW + 1)

        // Chave ligando pauta e tab.
        ctx.strokeStyle = ink
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.moveTo(8, staffTop)
        ctx.bezierCurveTo(2, staffTop + 10, 8, (staffTop + tabBottom) / 2 - 10, 3, (staffTop + tabBottom) / 2)
        ctx.bezierCurveTo(8, (staffTop + tabBottom) / 2 + 10, 2, tabBottom - 10, 8, tabBottom)
        ctx.stroke()

        // Linhas da pauta e da tab.
        ctx.strokeStyle = dim
        ctx.lineWidth = 1
        for (var l = 0; l < 5; ++l) {
            var ly = Math.round(staffTop + l * gap) + 0.5
            ctx.beginPath(); ctx.moveTo(12, ly); ctx.lineTo(lineEnd, ly); ctx.stroke()
        }
        for (var t = 0; t < 6; ++t) {
            var ty = Math.round(tabTop + t * tabGap) + 0.5
            ctx.beginPath(); ctx.moveTo(12, ty); ctx.lineTo(lineEnd, ty); ctx.stroke()
        }
        ctx.beginPath(); ctx.moveTo(12.5, staffTop); ctx.lineTo(12.5, tabBottom); ctx.stroke()
        drawClef(ctx, ink)

        // Número do primeiro compasso da linha.
        ctx.fillStyle = dim
        ctx.font = "11px sans-serif"
        ctx.fillText(String(measures[0].number), 14, staffTop - gap * 2.6)

        for (var m = 0; m < count; ++m) {
            var meas = measures[m]
            var x0 = clefW + m * mW
            var shape = shapeOf(meas.chord, meas.voicing)
            var name = Arara.CypherMusic.transposeChord(meas.chord, semitones)

            // Barra de compasso no fim (dupla quando a parte termina).
            ctx.strokeStyle = ink
            ctx.lineWidth = meas.repeat ? 2.5 : 1
            var bx = Math.round(x0 + mW) - 0.5
            ctx.beginPath(); ctx.moveTo(bx, staffTop); ctx.lineTo(bx, staffBottom); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(bx, tabTop); ctx.lineTo(bx, tabBottom); ctx.stroke()
            if (meas.repeat) {
                ctx.fillStyle = accent
                ctx.font = "bold 11px sans-serif"
                var rt = meas.repeat + "×"
                ctx.fillText(rt, bx - ctx.measureText(rt).width - 4, staffTop - 5)
            }

            // Nome da parte e do acorde.
            if (meas.label) {
                ctx.fillStyle = accent
                ctx.font = "bold 11px sans-serif"
                ctx.fillText(meas.label.toUpperCase(), x0 + 4, 12)
            }
            ctx.fillStyle = chordColor
            ctx.font = "bold 15px sans-serif"
            ctx.fillText(name, x0 + 6, 30)

            if (!shape) continue
            var events = eventsOf(shape, meas.pattern || root.pattern)
            var slotW = (mW - 14) / Math.max(1, events.length)
            var open = [40, 45, 50, 55, 59, 64]
            var stems = []
            for (var i = 0; i < events.length; ++i) {
                var ev = events[i]
                var cx = x0 + 10 + slotW * (i + 0.5)
                var muted = Examples.isMute(ev.code)

                // Tab: casa em cada corda tocada.
                ctx.font = "bold 11px sans-serif"
                for (var k = 0; k < ev.strings.length; ++k) {
                    var sIdx = ev.strings[k]
                    var label = muted ? "x" : String(shape.frets[sIdx])
                    var tyy = tabTop + (5 - sIdx) * tabGap
                    var tw = ctx.measureText(label).width
                    ctx.fillStyle = Theme.card
                    ctx.fillRect(cx - tw / 2 - 2, tyy - 6, tw + 4, 12)
                    ctx.fillStyle = sIdx === shape.root && Examples.plain(ev.code) === "B" ? chordColor : ink
                    ctx.fillText(label, cx - tw / 2, tyy + 4)
                }

                // Pauta.
                if (ev.strings.length === 0) {
                    ctx.fillStyle = dim
                    ctx.strokeStyle = dim
                    ctx.lineWidth = 1.4
                    var ry = staffTop + gap * 1.5
                    ctx.beginPath(); ctx.arc(cx - 2, ry, 1.8, 0, Math.PI * 2); ctx.fill()
                    ctx.beginPath(); ctx.moveTo(cx - 1, ry + 1); ctx.lineTo(cx + 3, ry - 1); ctx.lineTo(cx - 1, ry + gap * 2); ctx.stroke()
                    stems.push(null)
                    continue
                }
                var minY = 1e9, maxY = -1e9, prevStep = -100
                for (var n = 0; n < ev.strings.length; ++n) {
                    var s = ev.strings[n]
                    var sp = Examples.spell(open[s] + shape.frets[s], name)
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
                    if (muted) {
                        ctx.strokeStyle = ink
                        ctx.lineWidth = 1.6
                        ctx.beginPath()
                        ctx.moveTo(nx - 3.5, y - 3); ctx.lineTo(nx + 3.5, y + 3)
                        ctx.moveTo(nx - 3.5, y + 3); ctx.lineTo(nx + 3.5, y - 3)
                        ctx.stroke()
                    } else {
                        ctx.fillStyle = Examples.plain(ev.code) === "B" ? chordColor : accent
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
                }
                var stTop = minY - gap * 3.5
                ctx.strokeStyle = ink
                ctx.lineWidth = 1.2
                ctx.beginPath(); ctx.moveTo(cx + 4.5, maxY); ctx.lineTo(cx + 4.5, stTop); ctx.stroke()
                stems.push({ x: cx + 4.5, y: stTop })
            }
            // Colcheias em pares.
            ctx.strokeStyle = ink
            ctx.fillStyle = ink
            for (var p = 0; p < stems.length; p += 2) {
                var a = stems[p], b = p + 1 < stems.length ? stems[p + 1] : null
                if (a && b) {
                    var y0 = Math.min(a.y, b.y)
                    ctx.fillRect(a.x - 0.6, y0, b.x - a.x + 1.2, 3.5)
                    ctx.lineWidth = 1.2
                    ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(a.x, y0); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(b.x, b.y); ctx.lineTo(b.x, y0); ctx.stroke()
                } else if (a || b) {
                    var one = a || b
                    ctx.lineWidth = 1.6
                    ctx.beginPath()
                    ctx.moveTo(one.x, one.y)
                    ctx.bezierCurveTo(one.x + 2, one.y + 5, one.x + 9, one.y + 7, one.x + 6, one.y + 14)
                    ctx.stroke()
                }
            }
        }
    }
}
