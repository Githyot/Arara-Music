import QtQuick
import AraraCypher

// Legenda dos dedos: uma mão com cada dedo na cor usada nos contornos da tab
// (1 indicador, 2 médio, 3 anelar, 4 mínimo; P = polegar).
Item {
    id: root
    property real zoom: 1
    implicitWidth: 100 * zoom
    implicitHeight: 172 * zoom

    Canvas {
        id: canvas
        width: 100; height: 108
        scale: root.zoom
        transformOrigin: Item.TopLeft
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.translate(8, 0)
            var skin = Theme.dark ? "#3d3846" : "#f6f5f4"
            var edge = Theme.textDim
            function rr(x, y, w, h, r) {
                ctx.beginPath()
                ctx.moveTo(x + r, y)
                ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r)
                ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
                ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r)
                ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r)
                ctx.closePath()
            }
            // Dedos: [x, topo, cor, rótulo] — indicador, médio, anelar, mínimo.
            var fingers = [[24, 14, 1], [39, 4, 2], [54, 10, 3], [69, 24, 4]]
            ctx.lineWidth = 2
            for (var i = 0; i < fingers.length; ++i) {
                var f = fingers[i]
                rr(f[0], f[1], 13, 66 - f[1], 6.5)
                ctx.fillStyle = skin; ctx.fill()
                ctx.strokeStyle = Theme.fingerColors[f[2]]; ctx.lineWidth = 2.5; ctx.stroke()
                ctx.fillStyle = Theme.fingerColors[f[2]]
                ctx.font = "bold 12px sans-serif"
                var t = String(f[2])
                ctx.fillText(t, f[0] + 6.5 - ctx.measureText(t).width / 2, f[1] + 15)
            }
            // Polegar, de lado.
            ctx.save()
            ctx.translate(14, 74); ctx.rotate(-0.75)
            rr(-6, -30, 13, 34, 6.5)
            ctx.fillStyle = skin; ctx.fill()
            ctx.strokeStyle = Theme.fingerColors[5]; ctx.lineWidth = 2.5; ctx.stroke()
            ctx.restore()
            ctx.fillStyle = Theme.fingerColors[5]
            ctx.font = "bold 11px sans-serif"
            ctx.fillText("P", 1, 62)
            // Palma.
            rr(20, 56, 64, 46, 14)
            ctx.fillStyle = skin; ctx.fill()
            ctx.strokeStyle = edge; ctx.lineWidth = 2; ctx.stroke()
        }
        Connections {
            target: Theme
            function onDarkChanged() { canvas.requestPaint() }
            function onStyleChanged() { canvas.requestPaint() }
        }
    }
    Column {
        y: 110 * root.zoom
        x: 26 * root.zoom
        Repeater {
            model: ["1 indicador", "2 médio", "3 anelar", "4 mínimo", "P polegar"]
            Text {
                required property string modelData
                required property int index
                text: modelData
                color: Theme.fingerColors[index + 1]
                font.family: Theme.fontFamily
                font.pixelSize: 11 * root.zoom
                font.bold: true
            }
        }
    }
}
