import QtQuick
import AraraCypher

// Braço para digitar uma tab nota por nota: toque na casa e a nota entra na
// tab. Com "Notas juntas" ligado, as casas tocadas ficam marcadas e entram
// todas na mesma coluna quando toca em "Pôr na tab".
Column {
    id: root
    property int frets: 15
    property bool together: false
    property var pending: []           // [{ string, fret }] no modo "notas juntas"
    // Com marks (lista de { string, fret }), o braço mostra essas notas e o
    // toque numa casa só avisa com picked() (o editor visual decide o que fazer).
    property var marks: null
    signal picked(int string, int fret)
    signal column(var notes)           // notas de uma coluna da tab
    signal bar()
    signal rest()
    signal undo()

    spacing: 8

    readonly property real cellW: Math.max(30, Math.min(52, (width - 34) / (frets + 1)))
    readonly property real rowH: 30
    readonly property var names: ["E", "A", "D", "G", "B", "e"]

    function isPending(s, f) {
        if (marks) {
            for (var j = 0; j < marks.length; ++j)
                if (marks[j].string === s && marks[j].fret === f) return true
            return false
        }
        for (var i = 0; i < pending.length; ++i)
            if (pending[i].string === s && pending[i].fret === f) return true
        return false
    }

    function tap(s, f) {
        if (marks) { picked(s, f); return }
        if (!together) {
            column([{ string: s, fret: f }])
            return
        }
        // Uma nota por corda: tocar outra casa na mesma corda troca a nota.
        var next = pending.filter(function (n) { return n.string !== s })
        if (!isPending(s, f)) next.push({ string: s, fret: f })
        pending = next
    }

    Flickable {
        width: parent.width
        height: board.height
        contentWidth: board.width
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Item {
            id: board
            width: 34 + root.cellW * (root.frets + 1)
            height: root.rowH * 6 + 22

            // Números das casas.
            Repeater {
                model: root.frets + 1
                Text {
                    required property int index
                    x: 34 + index * root.cellW
                    width: root.cellW
                    y: root.rowH * 6 + 4
                    horizontalAlignment: Text.AlignHCenter
                    text: index === 0 ? "solta" : index
                    color: [3, 5, 7, 9, 12, 15].indexOf(index) >= 0 ? Theme.text : Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: [3, 5, 7, 9, 12, 15].indexOf(index) >= 0 ? Font.Bold : Font.Normal
                }
            }

            // Pestana (fim da casa 0) e trastes.
            Repeater {
                model: root.frets + 1
                Rectangle {
                    required property int index
                    x: 34 + (index + 1) * root.cellW - width / 2
                    y: root.rowH / 2
                    width: index === 0 ? 4 : 1.5
                    height: root.rowH * 5
                    color: index === 0 ? Theme.text : Theme.border
                }
            }

            // Cordas, do Mi agudo (em cima) ao Mi grave.
            Repeater {
                model: 6
                Item {
                    id: stringRow
                    required property int index
                    readonly property int s: 5 - index
                    y: index * root.rowH
                    width: board.width
                    height: root.rowH

                    Text {
                        width: 26
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: root.names[stringRow.s]
                        color: Theme.chord
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSize
                        font.weight: Font.Bold
                    }
                    Rectangle {
                        x: 34
                        width: root.cellW * (root.frets + 1)
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1 + stringRow.s * 0.35
                        color: Theme.textDim
                    }
                    Repeater {
                        model: root.frets + 1
                        Rectangle {
                            id: spot
                            required property int index
                            readonly property bool marked: (root.marks || root.pending).length >= 0 && root.isPending(stringRow.s, index)
                            x: 34 + index * root.cellW + (root.cellW - width) / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            radius: 12
                            color: marked ? Theme.accent
                                 : hover.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                                 : "transparent"
                            Text {
                                anchors.centerIn: parent
                                visible: spot.marked || hover.containsMouse
                                text: spot.index
                                color: spot.marked ? Theme.accentFg : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                anchors.margins: -3
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.tap(stringRow.s, spot.index)
                            }
                        }
                    }
                }
            }
        }
    }

    Flow {
        visible: !root.marks
        width: parent.width
        spacing: 6
        AppButton {
            text: root.together ? "Notas juntas: sim" : "Notas juntas: não"
            onClicked: { root.together = !root.together; root.pending = [] }
        }
        AppButton {
            visible: root.together
            enabled: root.pending.length > 0
            suggested: true
            text: "Pôr na tab"
            onClicked: { root.column(root.pending); root.pending = [] }
        }
        AppButton { text: "Pausa"; onClicked: root.rest() }
        AppButton { text: "Barra |"; onClicked: root.bar() }
        AppButton { text: "Desfazer"; onClicked: { root.pending = []; root.undo() } }
    }
}
