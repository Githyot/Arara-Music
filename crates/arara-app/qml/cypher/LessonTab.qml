import QtQuick
import QtQuick.Layouts
import AraraCypher
import io.github.arara as Arara

// Visualização de aula para uma tab de dedilhado: a tab grande, deitada,
// com o acorde escrito em cima, os números em cima das linhas das cordas, a
// seta da batida embaixo de cada nota e, ao lado, o desenho do acorde da vez.
// "Tocar" anda pelas notas no BPM da música (uma colcheia por nota).
Item {
    id: root
    property string tab
    property var song: null
    property int semitones: 0
    property int capo: 0
    property int bpm: 80
    property real zoom: 1
    signal beat(bool strong)

    readonly property var systems: tab ? JSON.parse(Arara.CypherMusic.lessonTab(tab)) : []
    // Todas as notas em ordem, com o acorde que vale em cada uma.
    readonly property var flat: {
        var out = [], chord = ""
        for (var s = 0; s < systems.length; ++s) {
            var sys = systems[s]
            for (var e = 0; e < sys.events.length; ++e) {
                var ev = sys.events[e]
                for (var c = 0; c < sys.chords.length; ++c)
                    if (sys.chords[c].col <= ev.col + 1) chord = sys.chords[c].name
                out.push({ system: s, event: e, chord: chord })
            }
        }
        return out
    }
    property int cur: -1
    readonly property string firstChord: {
        for (var s = 0; s < systems.length; ++s) if (systems[s].chords.length) return systems[s].chords[0].name
        return ""
    }
    readonly property string currentChord: cur >= 0 && cur < flat.length && flat[cur].chord ? flat[cur].chord : firstChord
    function t(name) { return Arara.CypherMusic.transposeChord(Examples.chordName(name), semitones) }

    property bool playing: false
    property real t0: 0
    Timer {
        interval: 5
        repeat: true
        running: root.playing
        onTriggered: {
            var n = Math.floor((Date.now() - root.t0) / (30000 / root.bpm))
            if (n >= root.flat.length) { root.playing = false; return }
            if (n !== root.cur) { root.cur = n; if (n % 2 === 0) root.beat(n % 8 === 0) }
        }
    }
    function toggle() {
        if (playing) { playing = false; return }
        var start = cur >= 0 && cur < flat.length - 1 ? cur : 0
        t0 = Date.now() - start * (30000 / bpm)
        cur = start - 1
        playing = true
    }

    readonly property real diagramW: 150 * zoom
    readonly property real rowH: 24 * zoom
    readonly property real labelW: 30 * zoom
    readonly property real tabW: Math.max(120, width - diagramW - 16)

    implicitHeight: Math.max(col.implicitHeight, side.implicitHeight)
    visible: systems.length > 0

    Column {
        id: col
        width: root.tabW
        spacing: 10

        Row {
            spacing: 8
            AppButton {
                text: root.playing ? "Parar" : (root.cur > 0 ? "Continuar" : "Tocar")
                suggested: !root.playing
                onClicked: root.toggle()
            }
            AppButton {
                visible: root.cur > 0 && !root.playing
                text: "Do começo"
                flat: true
                onClicked: { root.cur = -1; root.toggle() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.bpm + " BPM"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }

        Repeater {
            model: root.systems
            Rectangle {
                id: sysBox
                required property var modelData
                required property int index
                readonly property real cw: (width - root.labelW - 16) / Math.max(modelData.width, 16)
                width: col.width
                height: root.rowH * 8 + 12
                radius: Theme.radiusSmall
                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0.04)

                function xOf(c) { return root.labelW + 8 + (c + 0.5) * cw }

                // Acordes em cima.
                Repeater {
                    model: sysBox.modelData.chords
                    Text {
                        required property var modelData
                        x: sysBox.xOf(modelData.col) - 4
                        y: 4
                        text: root.t(modelData.name)
                        color: Theme.textDim
                        font.family: Theme.monoFamily
                        font.pixelSize: 15 * root.zoom
                        font.bold: true
                    }
                }
                // Cordas com o nome na esquerda.
                Repeater {
                    model: 6
                    Item {
                        required property int index
                        readonly property int string: 5 - index
                        y: root.rowH * (index + 1) + 2
                        width: sysBox.width
                        height: root.rowH
                        Rectangle {
                            x: 6
                            width: root.rowH * 0.8; height: width; radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: "transparent"
                            border.width: 1.5
                            border.color: Theme.chord
                            Text {
                                anchors.centerIn: parent
                                text: ["E", "A", "D", "G", "B", "e"][parent.parent.string]
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 11 * root.zoom
                                font.bold: true
                            }
                        }
                        Rectangle {
                            x: root.labelW + 6
                            width: parent.width - x - 8
                            height: 1
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.textDim
                            opacity: 0.5
                        }
                    }
                }
                // Barras de compasso.
                Repeater {
                    model: sysBox.modelData.bars
                    Rectangle {
                        required property var modelData
                        x: sysBox.xOf(modelData)
                        y: root.rowH * 1.5 + 2
                        width: 1.5
                        height: root.rowH * 5
                        color: Theme.textDim
                    }
                }
                // Notas e setas.
                Repeater {
                    model: sysBox.modelData.events
                    Item {
                        id: ev
                        required property var modelData
                        required property int index
                        readonly property bool active: root.cur >= 0 && root.cur < root.flat.length
                                                       && root.flat[root.cur].system === sysBox.index
                                                       && root.flat[root.cur].event === index
                        x: sysBox.xOf(modelData.col) - width / 2
                        width: Math.max(20, sysBox.cw * 2.4)
                        height: sysBox.height
                        Repeater {
                            model: ev.modelData.notes
                            Rectangle {
                                required property var modelData
                                // Dedo da forma do acorde da vez, se a nota for dessa forma.
                                readonly property var shape: {
                                    var i = 0
                                    for (var k = 0; k < root.flat.length; ++k)
                                        if (root.flat[k].system === sysBox.index && root.flat[k].event === ev.index) i = k
                                    var name = root.flat.length ? root.flat[i].chord : ""
                                    return name ? Examples.shape(Examples.chordName(name), 0,
                                                                 root.song ? Examples.voicing(root.song, name) : null) : null
                                }
                                readonly property int finger: shape && shape.frets[modelData.string] === modelData.fret
                                                              ? (shape.fingers[modelData.string] || 0) : 0
                                border.width: finger > 0 ? 1.6 : 0
                                border.color: Theme.fingerColors[finger]
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: root.rowH * (6 - modelData.string) + 2 + (root.rowH - height) / 2
                                width: Math.max(noteText.implicitWidth + 8, height)
                                height: root.rowH - 2
                                radius: height / 2
                                color: "transparent"
                                Text {
                                    id: noteText
                                    anchors.centerIn: parent
                                    text: (modelData.tech || "") + (modelData.fret === 255 ? "x" : modelData.fret)
                                    color: ev.active ? Theme.chord : Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: (ev.active ? 19 : 16) * root.zoom
                                    font.bold: true
                                }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: root.rowH * 7 + 2
                            text: ev.modelData.arrow ? Examples.strokeArrow(ev.modelData.arrow) : ""
                            color: ev.active ? Theme.chord : Theme.textDim
                            font.pixelSize: (ev.active ? 22 : 18) * root.zoom
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                for (var i = 0; i < root.flat.length; ++i)
                                    if (root.flat[i].system === sysBox.index && root.flat[i].event === ev.index) root.cur = i
                            }
                        }
                    }
                }
            }
        }
    }

    // Acorde da vez, ao lado (fica parado enquanto a tab rola).
    Column {
        id: side
        x: root.width - root.diagramW
        width: root.diagramW
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.currentChord ? root.t(root.currentChord) : ""
            color: Theme.chord
            font.family: Theme.monoFamily
            font.pixelSize: 24 * root.zoom
            font.bold: true
        }
        Text {
            visible: root.capo > 0
            anchors.horizontalCenter: parent.horizontalCenter
            text: "capo na " + root.capo + "ª casa"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        ChordDiagram {
            anchors.horizontalCenter: parent.horizontalCenter
            cellW: 20 * root.zoom
            cellH: 26 * root.zoom
            chord: root.currentChord ? Examples.chordName(root.currentChord) : "C"
            voicing: root.song && root.currentChord ? Examples.voicing(root.song, root.currentChord) : null
            semitones: root.semitones
        }
        HandLegend {
            anchors.horizontalCenter: parent.horizontalCenter
            zoom: Math.min(root.zoom, 1.2)
        }
    }
}
