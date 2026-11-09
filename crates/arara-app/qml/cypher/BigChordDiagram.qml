import QtQuick
import AraraCypher

// Desenho grande de um acorde, para enxergar de longe enquanto toca:
// braço em pé, casa inicial ao lado ("3ª"), barra escrita "PESTANA" quando o
// indicador prende várias cordas, bolinhas com o número do dedo e, embaixo,
// O para corda que soa e X para corda que não toca.
Item {
    id: root
    property string chord
    property int semitones: 0
    property real cellW: 30
    property real cellH: 38

    property var voicing: null        // forma tirada da aula (opcional)
    readonly property var shape: Examples.shape(chord, semitones, voicing)
    readonly property int frets: 5
    readonly property real line: 3
    readonly property real gridW: cellW * 5
    readonly property real gridH: cellH * frets
    readonly property real leftPad: 46
    // Capo desenhado em cima do braço (forma com "capo": n), como nos vídeos.
    readonly property int capo: voicing && voicing.capo ? voicing.capo : 0
    readonly property real topPad: 10 + (capo > 0 ? 30 : 0)
    readonly property color gridColor: Theme.dark ? "#d9d9d9" : "#5e5c64"

    readonly property var barre: {
        if (!shape) return null
        var first = -1, last = -1, fret = 0
        for (var i = 0; i < 6; ++i) {
            if (shape.fingers[i] === 1) {
                if (first < 0) { first = i; fret = shape.frets[i] }
                if (shape.frets[i] === fret) last = i
            }
        }
        return last > first ? { first: first, last: last, fret: fret } : null
    }

    implicitWidth: leftPad + gridW + line + 10
    implicitHeight: topPad + gridH + 40
    visible: shape !== null

    // Capo: barra escura com "CAPO" e a casa ao lado.
    Rectangle {
        visible: root.capo > 0
        x: root.leftPad - 6
        y: 4
        width: root.gridW + root.line + 12
        height: 20
        radius: 4
        color: Theme.dark ? "#f0f0f0" : "#241f31"
        Text {
            anchors.centerIn: parent
            text: "C A P O"
            color: Theme.dark ? "#241f31" : "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.bold: true
        }
    }
    Text {
        visible: root.capo > 0
        text: root.capo + "ª"
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 16
        font.bold: true
        x: root.leftPad - 10 - width
        y: 4 + 10 - height / 2
    }

    // Topo do braço: grosso quando o acorde começa na pestana do violão.
    Rectangle {
        x: root.leftPad
        y: root.topPad
        width: root.gridW + root.line
        height: root.shape && root.shape.base === 1 ? 10 : root.line
        color: root.gridColor
    }

    // Casas.
    Repeater {
        model: root.frets
        Rectangle {
            required property int index
            x: root.leftPad
            y: root.topPad + (index + 1) * root.cellH
            width: root.gridW + root.line
            height: root.line
            color: root.gridColor
        }
    }

    // Cordas.
    Repeater {
        model: 6
        Rectangle {
            required property int index
            x: root.leftPad + index * root.cellW
            y: root.topPad
            width: root.line
            height: root.gridH + root.line
            color: root.gridColor
        }
    }

    // Número da casa inicial.
    Text {
        visible: root.shape && root.shape.base > 1
        text: root.shape ? root.shape.base + "ª" : ""
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: 22
        font.bold: true
        x: root.leftPad - root.cellW * 0.45 - width - 4
        y: root.topPad + root.cellH / 2 - height / 2 + root.line
    }

    // Pestana.
    Rectangle {
        visible: root.barre !== null
        readonly property real h: root.cellH * 0.5
        x: root.barre ? root.leftPad + root.barre.first * root.cellW - 8 : 0
        y: root.barre ? root.topPad + (root.barre.fret - root.shape.base + 0.5) * root.cellH - h / 2 + root.line / 2 : 0
        width: root.barre ? (root.barre.last - root.barre.first) * root.cellW + 16 + root.line : 0
        height: h
        radius: 6
        color: Theme.accent
        Text {
            visible: root.barre && root.barre.last - root.barre.first >= 3
            anchors.centerIn: parent
            text: "PESTANA"
            color: "#ffffff"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 3
        }
    }

    // Dedos (os que não fazem parte da pestana).
    Repeater {
        model: 6
        Rectangle {
            id: dot
            required property int index
            readonly property int f: root.shape ? root.shape.frets[index] : -1
            readonly property int finger: root.shape ? root.shape.fingers[index] : 0
            readonly property bool inBarre: root.barre && finger === 1 && f === root.barre.fret
            readonly property real d: root.cellW * 0.85
            visible: f > 0 && !inBarre
            width: d
            height: d
            radius: d / 2
            color: root.shape && index === root.shape.root ? Theme.chord : Theme.accent
            x: root.leftPad + index * root.cellW - d / 2 + root.line / 2
            y: root.shape ? root.topPad + (f - root.shape.base + 0.5) * root.cellH - d / 2 + root.line / 2 : 0
            Text {
                anchors.centerIn: parent
                text: dot.finger === 5 ? "P" : dot.finger > 0 ? dot.finger : ""
                color: "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
            }
        }
    }

    // Embaixo: O = corda solta, X = não toca; corda presa fica sem marca.
    Repeater {
        model: 6
        Text {
            required property int index
            readonly property bool muted: root.shape && root.shape.frets[index] < 0
            readonly property bool open: root.shape && root.shape.frets[index] === 0
            text: muted ? "X" : open ? "O" : ""
            color: muted ? Theme.destructive : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.bold: true
            x: root.leftPad + index * root.cellW - width / 2 + root.line / 2
            y: root.topPad + root.gridH + 8
        }
    }
}
