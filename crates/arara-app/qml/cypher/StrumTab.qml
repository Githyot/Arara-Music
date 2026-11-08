import QtQuick
import QtQuick.Shapes
import AraraCypher

// Tab "deitada" de um acorde tocado com uma batida, no estilo das videoaulas:
// seis linhas (e B G D A E, do agudo para o grave), o número da casa em cima
// da linha da corda (com um contorno na cor do dedo que aperta), "×" para
// corda abafada e a direção da palheta embaixo de cada tempo.
//
// Códigos da batida (um por tempo):
//   "B"  baixo: só a corda da fundamental, palheta para baixo
//   "D"  todas as cordas do acorde, para baixo
//   "d"  cordas do acorde sem o baixo, para baixo
//   "U"  as três cordas mais agudas do acorde, para cima
//   "X"  abafado: palheta para baixo com a mão abafando as cordas ("XU" para cima)
//   ""   pausa
Item {
    id: root
    property string chord
    property int semitones: 0
    property var pattern: []
    property var counts: []
    property bool showStringNames: true
    property bool dashes: true        // traços das cordas (a tab comprida desenha linhas inteiras)
    property bool editing: false      // tocar numa casa ou numa seta para mudar
    property int selString: -1        // corda escolhida para editar (realçada)
    property int selStep: -1          // tempo escolhido
    signal noteClicked(int string, int step)
    signal stepClicked(int step)

    readonly property real cellW: 22
    readonly property real rowH: 20
    readonly property real labelW: showStringNames ? 30 : 6
    readonly property var stringNames: ["E", "A", "D", "G", "B", "e"]

    property var voicing: null        // forma tirada da aula (opcional)
    // Casas escritas à mão neste compasso: { "tempo:corda": { f: casa (255 = x), g: dedo } }.
    property var cells: ({})
    function cellAt(step, string) { return cells ? cells[step + ":" + string] : undefined }
    function fingerAt(step, string) {
        var c = cellAt(step, string)
        if (c && c.g !== undefined) return c.g
        if (c && c.f !== undefined) return 0
        return shape ? (shape.fingers[string] || 0) : 0
    }
    property int rev: 0               // muda quando a forma é editada no lugar
    // Acorde que o app não conhece (ex.: Em7(9)) e sem forma salva: tab vazia,
    // para dar para pôr as notas uma a uma.
    readonly property var shape: rev, Examples.shape(chord, semitones, voicing) || Examples.blankShape()

    // Para cada tempo: lista de 6 valores (corda 0 = Mi grave) com a casa,
    // "x" para abafada ou null se a corda não soa.
    readonly property var columns: {
        var cols = []
        if (!shape) return cols
        for (var i = 0; i < pattern.length; ++i) {
            var c = [null, null, null, null, null, null]
            var code = pattern[i]
            var strings = Examples.isPick(code)
                ? Examples.pickStrings(code).filter(function (s) { return shape.frets[s] >= 0 || cellAt(i, s) })
                : Examples.strokeStrings(shape, code)
            for (var k = 0; k < strings.length; ++k) {
                var own = cellAt(i, strings[k])
                c[strings[k]] = Examples.isMute(code) ? "x"
                    : own && own.f !== undefined ? (own.f === 255 ? "x" : own.f) : shape.frets[strings[k]]
            }
            cols.push(c)
        }
        return cols
    }

    implicitWidth: labelW + pattern.length * cellW + 6
    implicitHeight: rowH * 8 + 6
    visible: shape !== null

    // ---- Direção da palheta ----
    Repeater {
        model: root.pattern.length
        Text {
            required property int index
            readonly property string code: root.pattern[index]
            x: root.labelW + index * root.cellW
            width: root.cellW
            y: root.rowH * 6 + 2
            height: root.rowH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: code === "" ? (root.editing ? "·" : "") : Examples.strokeArrow(code)
            color: Examples.isMute(code) || code === "" ? Theme.textDim : Theme.chord
            font.pixelSize: Examples.isMute(code) ? 12 : 17
            font.bold: true
            Rectangle {
                visible: root.editing
                anchors.fill: parent
                anchors.margins: 1
                radius: 4
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, arrowMouse.containsMouse ? 0.9 : 0.3)
            }
            MouseArea {
                id: arrowMouse
                anchors.fill: parent
                enabled: root.editing
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.stepClicked(parent.index)
            }
        }
    }

    // ---- Cordas ----
    Repeater {
        model: 6
        Item {
            id: stringRow
            required property int index
            readonly property int string: 5 - index   // linha de cima = Mi agudo
            x: 0
            y: root.rowH * index
            width: root.implicitWidth
            height: root.rowH

            // Nome da corda numa palheta.
            Item {
                visible: root.showStringNames
                width: 24
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                Shape {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.samples: 4
                    ShapePath {
                        strokeColor: Theme.accent
                        strokeWidth: 1.6
                        fillColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                        PathSvg { path: "M9 1.5 C3.5 1.5 1 5 1 9 C1 13 3.5 16.5 9 16.5 C14 16.5 19 12 23 9 C19 6 14 1.5 9 1.5 Z" }
                    }
                }
                Text {
                    x: 3
                    width: 13
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: root.stringNames[stringRow.string]
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Repeater {
                model: root.pattern.length
                Item {
                    id: cell
                    required property int index
                    readonly property var value: root.columns.length > index ? root.columns[index][stringRow.string] : null
                    x: root.labelW + index * root.cellW
                    width: root.cellW
                    height: root.rowH

                    // Realce da corda escolhida e área de toque no modo de edição.
                    Rectangle {
                        readonly property bool chosen: root.selString === stringRow.string && root.selStep === cell.index
                        visible: root.editing && (chosen || cellMouse.containsMouse)
                        anchors.fill: parent
                        radius: 4
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, chosen ? 0.3 : 0.12)
                        border.width: chosen ? 1.5 : 0
                        border.color: Theme.accent
                    }
                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        enabled: root.editing
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.noteClicked(stringRow.string, cell.index)
                    }
                    Text {
                        visible: root.editing && cell.value === null && cellMouse.containsMouse
                        anchors.centerIn: parent
                        text: "+"
                        color: Theme.accent
                        font.pixelSize: 14
                        font.bold: true
                    }
                    // Linha da corda (tracejada, como nas aulas).
                    Rectangle {
                        visible: root.dashes && cell.value === null
                        anchors.centerIn: parent
                        width: root.cellW - 8
                        height: 1.5
                        color: Theme.textDim
                        opacity: 0.6
                    }
                    // Casa tocada: o número (na cor da casa), com contorno na cor do dedo.
                    // Corda solta junto de outras notas vira um anel pequeno; sozinha, fica o 0.
                    readonly property bool open: value === 0 && root.columns.length > index && root.columns[index].filter(function (v) { return v !== null }).length > 1
                    Rectangle {
                        visible: cell.open
                        anchors.centerIn: parent
                        width: 10; height: 10; radius: 5
                        color: Theme.card
                        border.width: 2
                        border.color: Theme.textDim
                    }
                    Rectangle {
                        readonly property int finger: cell.value !== null && cell.value !== "x"
                                                      ? root.fingerAt(cell.index, stringRow.string) : 0
                        visible: cell.value !== null && !cell.open
                        anchors.centerIn: parent
                        width: 19
                        height: 19
                        radius: 9.5
                        color: Theme.card     // esconde a linha da corda atrás do número
                        border.width: finger > 0 ? 1.6 : 0
                        border.color: Theme.fingerColors[finger]
                        Text {
                            anchors.centerIn: parent
                            text: cell.value === "x" ? "×" : (cell.value !== null ? cell.value : "")
                            color: cell.value === "x" ? Theme.textDim : parent.finger > 0 ? Theme.text : Theme.fretColor(cell.value)
                            font.family: Theme.fontFamily
                            font.pixelSize: String(cell.value).length > 1 ? 11 : 14
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    // ---- Contagem ----
    Repeater {
        model: root.pattern.length
        Text {
            required property int index
            x: root.labelW + index * root.cellW
            width: root.cellW
            y: root.rowH * 7 + 2
            height: root.rowH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.counts.length > index ? root.counts[index] : ""
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }
    }
}
