import QtQuick
import AraraCypher
import io.github.arara as Arara

// Partitura (pauta de guitarra) de um acorde tocado com a batida da música.
// Clave de sol com "8" embaixo, como é escrita a guitarra (soa uma oitava
// abaixo do escrito). Cada tempo da batida vira uma colcheia: as notas que a
// mão toca naquele tempo ficam empilhadas, "×" no abafado e pausa onde não toca.
// As notas saem da forma do acorde no braço, então seguem a transposição.
Canvas {
    id: root
    property string chord
    property int semitones: 0
    property var pattern: []
    property real zoom: 1
    readonly property real lw: width / zoom

    readonly property real gap: 9          // distância entre linhas da pauta
    readonly property real slotW: 28
    readonly property real clefW: 40
    readonly property real staffTop: {
        var top = 38
        for (var i = 0; i < events.length; ++i)
            for (var k = 0; k < events[i].length; ++k)
                top = Math.max(top, Examples.spell(events[i][k].midi, chord).step)
        return Math.max(gap * 6, (top - 38) * gap / 2 + gap * 3.5 + 10)
    }
    readonly property real staffBottom: staffTop + gap * 4

    property var voicing: null        // forma tirada da aula (opcional)
    readonly property var shape: Examples.shape(chord, semitones, voicing)

    // Para cada tempo: lista de { midi, muted } ou [] para pausa.
    readonly property var events: {
        var out = []
        if (!shape) return out
        var open = [40, 45, 50, 55, 59, 64]
        var played = []
        for (var s = 0; s < 6; ++s)
            if (shape.frets[s] >= 0) played.push(s)
        var upper = played.filter(function (s) { return s > shape.root })
        var top3 = played.slice(-3)
        for (var i = 0; i < pattern.length; ++i) {
            var code = pattern[i]
            var strings = Examples.strokeStrings(shape, code)
            var notes = []
            for (var k = 0; k < strings.length; ++k)
                notes.push({ midi: open[strings[k]] + shape.frets[strings[k]], muted: Examples.isMute(code) })
            out.push(notes)
        }
        return out
    }

    implicitWidth: (clefW + Math.max(1, pattern.length) * slotW + 10) * zoom
    implicitHeight: (staffBottom + gap * 6) * zoom
    visible: shape !== null

    onEventsChanged: requestPaint()
    onZoomChanged: requestPaint()
    onWidthChanged: requestPaint()
    Connections {
        target: Theme
        function onDarkChanged() { root.requestPaint() }
        function onStyleChanged() { root.requestPaint() }
    }

    // Altura escrita (uma oitava acima do som) -> posição diatônica e acidente.
    function spell(midi) {
        return Examples.spell(midi, Arara.CypherMusic.transposeChord(chord, semitones))
    }

    // Mi4 (linha de baixo da pauta) = passo diatônico 30.
    function yOf(step) { return staffBottom - (step - 30) * gap / 2 }

    function drawClef(ctx, color) {
        // Clave de sol estilizada.
        var x = 14, top = staffTop - gap * 1.6, bottom = staffBottom + gap * 1.8
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
        if (!shape) return
        ctx.scale(zoom, zoom)
        var ink = Theme.text
        var dim = Theme.textDim
        var accent = Theme.accent

        // Pauta.
        ctx.strokeStyle = dim
        ctx.lineWidth = 1
        for (var l = 0; l < 5; ++l) {
            var ly = Math.round(staffTop + l * gap) + 0.5
            ctx.beginPath(); ctx.moveTo(2, ly); ctx.lineTo(lw - 2, ly); ctx.stroke()
        }
        ctx.beginPath(); ctx.moveTo(lw - 2.5, staffTop); ctx.lineTo(lw - 2.5, staffBottom); ctx.stroke()
        drawClef(ctx, ink)

        var stemTops = []
        for (var i = 0; i < events.length; ++i) {
            var cx = clefW + i * slotW + slotW / 2
            var notes = events[i]
            if (notes.length === 0) {
                // Pausa de colcheia.
                ctx.fillStyle = dim
                ctx.strokeStyle = dim
                ctx.lineWidth = 1.4
                var ry = staffTop + gap * 1.5
                ctx.beginPath(); ctx.arc(cx - 2, ry, 1.8, 0, Math.PI * 2); ctx.fill()
                ctx.beginPath(); ctx.moveTo(cx - 1, ry + 1); ctx.lineTo(cx + 3, ry - 1); ctx.lineTo(cx - 1, ry + gap * 2); ctx.stroke()
                stemTops.push(null)
                continue
            }
            var minY = 1e9, maxY = -1e9
            var prevStep = -100
            for (var n = 0; n < notes.length; ++n) {
                var sp = spell(notes[n].midi)
                var y = yOf(sp.step)
                minY = Math.min(minY, y); maxY = Math.max(maxY, y)
                // Linhas suplementares.
                ctx.strokeStyle = dim
                ctx.lineWidth = 1
                for (var st = 28; st >= sp.step; st -= 2) {
                    var ly2 = Math.round(yOf(st)) + 0.5
                    ctx.beginPath(); ctx.moveTo(cx - 7, ly2); ctx.lineTo(cx + 7, ly2); ctx.stroke()
                }
                for (var st2 = 40; st2 <= sp.step; st2 += 2) {
                    var ly3 = Math.round(yOf(st2)) + 0.5
                    ctx.beginPath(); ctx.moveTo(cx - 7, ly3); ctx.lineTo(cx + 7, ly3); ctx.stroke()
                }
                // Segunda vizinha vai para o lado direito da haste.
                var nx = (sp.step - prevStep === 1) ? cx + 6 : cx
                prevStep = sp.step
                if (notes[n].muted) {
                    ctx.strokeStyle = ink
                    ctx.lineWidth = 1.6
                    ctx.beginPath()
                    ctx.moveTo(nx - 3.5, y - 3); ctx.lineTo(nx + 3.5, y + 3)
                    ctx.moveTo(nx - 3.5, y + 3); ctx.lineTo(nx + 3.5, y - 3)
                    ctx.stroke()
                } else {
                    ctx.fillStyle = n === 0 && i < pattern.length && pattern[i] === "B" ? Theme.chord : accent
                    ctx.save()
                    ctx.translate(nx, y)
                    ctx.rotate(-0.35)
                    ctx.scale(1.35, 1)
                    ctx.beginPath(); ctx.arc(0, 0, gap / 2 - 0.3, 0, Math.PI * 2); ctx.fill()
                    ctx.restore()
                }
                if (sp.acc !== 0 && !notes[n].muted) {
                    ctx.fillStyle = ink
                    ctx.font = "14px sans-serif"
                    ctx.fillText(sp.acc > 0 ? "♯" : "♭", cx - 16, y + 5)
                }
            }
            // Haste para cima.
            var top = minY - gap * 3.5
            ctx.strokeStyle = ink
            ctx.lineWidth = 1.2
            ctx.beginPath(); ctx.moveTo(cx + 4.5, maxY); ctx.lineTo(cx + 4.5, top); ctx.stroke()
            stemTops.push({ x: cx + 4.5, y: top })
        }

        // Barras (pares de colcheias) ou bandeirolas.
        ctx.strokeStyle = ink
        ctx.fillStyle = ink
        for (var p = 0; p < stemTops.length; p += 2) {
            var a = stemTops[p], b = p + 1 < stemTops.length ? stemTops[p + 1] : null
            if (a && b) {
                var y0 = Math.min(a.y, b.y)
                ctx.fillRect(a.x - 0.6, y0, b.x - a.x + 1.2, 3.5)
                // Alonga a haste até a barra.
                ctx.lineWidth = 1.2
                ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(a.x, y0); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(b.x, b.y); ctx.lineTo(b.x, y0); ctx.stroke()
            } else {
                var single = a || b
                if (single) {
                    ctx.lineWidth = 1.6
                    ctx.beginPath()
                    ctx.moveTo(single.x, single.y)
                    ctx.bezierCurveTo(single.x + 2, single.y + 5, single.x + 9, single.y + 7, single.x + 6, single.y + 14)
                    ctx.stroke()
                }
            }
        }
    }
}
