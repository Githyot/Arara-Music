import QtQuick
import AraraCypher
import io.github.arara as Arara

// Os acordes de uma parte numa tab só, comprida e contínua, como na partitura:
// cada acorde é um compasso (com a batida da parte), o nome do acorde em cima,
// barra de compasso entre eles e o nome das cordas no começo de cada linha.
Column {
    id: root
    property var chords: []           // tokens das partes ("Gm7@2" = forma 2)
    property var song: null
    property int semitones: 0
    property var pattern: ["D"]
    property var patterns: []          // tempos de cada compasso (se mudaram só ali)
    property var cells: []             // casas escritas à mão em cada compasso
    property var counts: []
    property real zoom: 1
    property int rev: 0                // muda quando a música é editada aqui
    property bool editing: false
    property int selIndex: -1          // compasso (acorde) escolhido para editar
    property int selString: -1
    property int selStep: -1
    signal noteClicked(int index, string token, int string, int step)
    signal stepClicked(int index, int step)

    readonly property real cellW: 22
    readonly property real rowH: 20
    readonly property real titleH: 26 * zoom
    readonly property real labelW: 30 * zoom
    // Largura do compasso: cabe a batida e o nome do acorde mais comprido.
    readonly property int nameLen: chords.reduce(function (m, c) { return Math.max(m, Examples.chordName(c).length) }, 0)
    readonly property real measureW: Math.max(Math.max(1, pattern.length) * cellW + 12, nameLen * 10.5 + 16) * zoom
    readonly property int perRow: Math.max(1, Math.floor((width - labelW - 4) / measureW))
    readonly property real stripH: titleH + (rowH * 8 + 6) * zoom

    spacing: 12

    Repeater {
        model: Math.ceil(root.chords.length / root.perRow)
        Row {
            id: line
            required property int index
            readonly property var items: root.chords.slice(index * root.perRow, (index + 1) * root.perRow)
            height: root.stripH

            // Nome das cordas, só no começo da linha.
            Item {
                width: root.labelW
                height: root.stripH
                Repeater {
                    model: 6
                    Rectangle {
                        required property int index
                        x: 4 * root.zoom
                        y: root.titleH + (root.rowH * index + root.rowH / 2) * root.zoom - height / 2
                        width: 18 * root.zoom; height: width; radius: width / 2
                        color: "transparent"
                        border.width: 1.4
                        border.color: Theme.chord
                        Text {
                            anchors.centerIn: parent
                            text: ["e", "B", "G", "D", "A", "E"][parent.index]
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 10 * root.zoom
                            font.bold: true
                        }
                    }
                }
                // Barra do começo da linha.
                Rectangle {
                    x: parent.width - 1.5
                    y: root.titleH + root.rowH / 2 * root.zoom
                    width: 1.5
                    height: root.rowH * 5 * root.zoom
                    color: Theme.textDim
                }
            }

            Repeater {
                model: line.items
                Item {
                    id: measure
                    required property string modelData
                    required property int index
                    readonly property int chordIndex: line.index * root.perRow + index
                    width: root.measureW
                    height: root.stripH
                    Text {
                        x: 8 * root.zoom
                        y: 2
                        text: Arara.CypherMusic.transposeChord(Examples.chordName(measure.modelData), root.semitones)
                        color: Theme.chord
                        font.family: Theme.monoFamily
                        font.pixelSize: 16 * root.zoom
                        font.bold: true
                    }
                    // Linhas das cordas por baixo (ligam um compasso no outro).
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            y: Math.round(root.titleH + (root.rowH * index + root.rowH / 2) * root.zoom)
                            width: measure.width
                            height: 1
                            color: Theme.textDim
                            opacity: 0.45
                        }
                    }
                    StrumTab {
                        x: 2 * root.zoom
                        y: root.titleH
                        scale: root.zoom
                        transformOrigin: Item.TopLeft
                        showStringNames: false
                        dashes: false
                        chord: Examples.chordName(measure.modelData)
                        voicing: root.rev, root.song ? Examples.voicing(root.song, measure.modelData) : null
                        semitones: root.semitones
                        pattern: root.patterns[measure.chordIndex] || root.pattern
                        cells: root.cells[measure.chordIndex] || ({})
                        counts: root.counts
                        editing: root.editing
                        selString: root.selIndex === measure.chordIndex ? root.selString : -1
                        selStep: root.selStep
                        rev: root.rev
                        onNoteClicked: (string, step) => root.noteClicked(measure.chordIndex, measure.modelData, string, step)
                        onStepClicked: (step) => root.stepClicked(measure.chordIndex, step)
                    }
                    // Barra de compasso.
                    Rectangle {
                        x: measure.width - 1.5
                        y: root.titleH + root.rowH / 2 * root.zoom
                        width: 1.5
                        height: root.rowH * 5 * root.zoom
                        color: Theme.textDim
                    }
                }
            }
        }
    }
}
