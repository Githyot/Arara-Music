import QtQuick
import AraraCypher

// Desenho de um acorde no braço do violão: 6 cordas (Mi grave à esquerda),
// 5 casas, bolinhas com o número do dedo, "×" para corda que não toca e
// "○" para corda solta. A bolinha da fundamental (nota que dá nome ao
// acorde) fica na cor de destaque.
Item {
    id: root
    property string chord
    property int semitones: 0
    property real cellW: 13
    property real cellH: 17

    property var voicing: null        // forma tirada da aula (opcional)
    readonly property var shape: Examples.shape(chord, semitones, voicing)
    readonly property int frets: 5
    readonly property real gridW: cellW * 5
    readonly property real gridH: cellH * frets
    readonly property real leftPad: 16
    readonly property real topPad: 14

    implicitWidth: leftPad + gridW + 8
    implicitHeight: topPad + gridH + 4
    visible: shape !== null

    // Casa inicial (ex.: "2ª") quando o acorde não começa na cabeça do violão.
    Text {
        visible: root.shape && root.shape.base > 1
        text: root.shape ? root.shape.base + "ª" : ""
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        x: 0
        y: root.topPad + root.cellH / 2 - height / 2
    }

    // Pestana do violão (traço grosso) ou linha da primeira casa.
    Rectangle {
        x: root.leftPad
        y: root.topPad - (root.shape && root.shape.base === 1 ? 3 : 1)
        width: root.gridW + 1
        height: root.shape && root.shape.base === 1 ? 4 : 1.5
        color: Theme.text
        radius: 1
    }

    // Casas (linhas horizontais).
    Repeater {
        model: root.frets
        Rectangle {
            required property int index
            x: root.leftPad
            y: root.topPad + (index + 1) * root.cellH
            width: root.gridW + 1
            height: 1
            color: Theme.textDim
            opacity: 0.7
        }
    }

    // Cordas (linhas verticais).
    Repeater {
        model: 6
        Rectangle {
            required property int index
            x: root.leftPad + index * root.cellW
            y: root.topPad
            width: 1
            height: root.gridH
            color: Theme.textDim
            opacity: 0.7
        }
    }

    // Marcas em cima: × não toca, ○ solta.
    Repeater {
        model: 6
        Text {
            required property int index
            readonly property int f: root.shape ? root.shape.frets[index] : -1
            visible: root.shape && f <= 0
            text: f < 0 ? "×" : "○"
            color: f < 0 ? Theme.textDim : (index === root.shape.root ? Theme.accent : Theme.text)
            font.pixelSize: 11
            font.bold: true
            x: root.leftPad + index * root.cellW - width / 2 + 0.5
            y: root.topPad - height - 2
        }
    }

    // Pestana com o dedo 1 quando várias cordas usam a mesma casa com o indicador.
    Rectangle {
        id: barre
        readonly property var info: {
            if (!root.shape) return null
            var first = -1, last = -1, fret = 0
            for (var i = 0; i < 6; ++i) {
                if (root.shape.fingers[i] === 1) {
                    if (first < 0) { first = i; fret = root.shape.frets[i] }
                    if (root.shape.frets[i] === fret) last = i
                }
            }
            return last > first ? { first: first, last: last, fret: fret } : null
        }
        visible: info !== null
        readonly property real d: root.cellW - 1
        x: info ? root.leftPad + info.first * root.cellW - d / 2 + 0.5 : 0
        y: info ? root.topPad + (info.fret - root.shape.base + 0.5) * root.cellH - d / 2 : 0
        width: info ? (info.last - info.first) * root.cellW + d : 0
        height: d
        radius: d / 2
        color: Theme.text
    }

    // Bolinhas dos dedos.
    Repeater {
        model: 6
        Rectangle {
            required property int index
            readonly property int f: root.shape ? root.shape.frets[index] : -1
            readonly property bool isRoot: root.shape && index === root.shape.root
            visible: f > 0
            readonly property real d: root.cellW - 1
            width: d
            height: d
            radius: d / 2
            color: isRoot ? Theme.accent : Theme.text
            x: root.leftPad + index * root.cellW - d / 2 + 0.5
            y: root.shape ? root.topPad + (f - root.shape.base + 0.5) * root.cellH - d / 2 : 0
            Text {
                anchors.centerIn: parent
                text: root.shape && root.shape.fingers[parent.index] === 5 ? "P" : root.shape && root.shape.fingers[parent.index] > 0 ? root.shape.fingers[parent.index] : ""
                color: Theme.dark ? "#000000" : "#ffffff"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.bold: true
            }
        }
    }
}
