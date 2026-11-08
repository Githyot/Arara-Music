import QtQuick
import QtQuick.Layouts
import AraraCypher
import AraraCypher.Audio

// Afinador pelo microfone: mostra a nota que está soando, quantos cents
// está acima ou abaixo e qual corda do violão (afinação padrão) é a mais perto.
Rectangle {
    id: page
    color: Theme.window

    Mic { id: mic }
    // Some quando a página não está à vista (não deixa o microfone ligado).
    onVisibleChanged: if (!visible) mic.active = false

    readonly property var names: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    readonly property var ptNames: ["Dó", "Dó♯", "Ré", "Ré♯", "Mi", "Fá", "Fá♯", "Sol", "Sol♯", "Lá", "Lá♯", "Si"]
    // Cordas soltas (MIDI) da 6ª à 1ª.
    readonly property var strings: [40, 45, 50, 55, 59, 64]
    readonly property var stringNames: ["E", "A", "D", "G", "B", "e"]
    property int target: -1                // corda escolhida; -1 = automático

    // Média das últimas leituras, para o ponteiro não tremer.
    property var recent: []
    property real freq: 0
    Connections {
        target: mic
        function onUpdated() {
            var f = mic.frequency
            if (f <= 0) { page.recent = []; page.freq = 0; return }
            var r = page.recent.slice()
            // Mudou de nota: recomeça a média.
            if (r.length && Math.abs(12 * Math.log2(f / r[r.length - 1])) > 0.7) r = []
            r.push(f)
            if (r.length > 5) r.shift()
            page.recent = r
            var s = r.slice().sort(function (a, b) { return a - b })
            page.freq = s[Math.floor(s.length / 2)]
        }
    }
    readonly property real midiF: freq > 0 ? 69 + 12 * Math.log2(freq / 440) : 0
    // Nota de referência: a corda escolhida ou a nota mais perto.
    readonly property int refMidi: {
        if (freq <= 0) return -1
        if (target >= 0) return strings[target]
        return Math.round(midiF)
    }
    readonly property real cents: refMidi < 0 ? 0 : (midiF - refMidi) * 100
    readonly property int nearString: {
        if (freq <= 0) return -1
        var best = 0
        for (var i = 1; i < 6; ++i) if (Math.abs(midiF - strings[i]) < Math.abs(midiF - strings[best])) best = i
        return Math.abs(midiF - strings[best]) < 2.5 ? best : -1
    }
    readonly property bool inTune: refMidi >= 0 && Math.abs(cents) < 5

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        HeaderBar { Layout.fillWidth: true; title: "Afinador" }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight + 40
            clip: true
            Column {
                id: col
                width: Math.min(parent.width - 2 * Theme.pagePadding, 620)
                x: (parent.width - width) / 2
                y: 20
                spacing: 18

                AppButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: mic.active ? "Desligar microfone" : "Ligar microfone"
                    suggested: !mic.active
                    onClicked: mic.active = !mic.active
                }
                Text {
                    visible: mic.error !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: mic.error
                    color: Theme.destructive
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                // Nota.
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.refMidi < 0 ? (mic.active ? "…" : "—") : page.names[page.refMidi % 12]
                        color: page.inTune ? Theme.success : Theme.chord
                        font.family: Theme.monoFamily
                        font.pixelSize: 96
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.refMidi < 0 ? (mic.active ? "Toque uma corda" : "Ligue o microfone e toque uma corda")
                                               : page.ptNames[page.refMidi % 12] + " " + (Math.floor(page.refMidi / 12) - 1)
                                                 + "  ·  " + page.freq.toFixed(1) + " Hz"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                    }
                }

                // Ponteiro: −50 a +50 cents.
                Item {
                    width: parent.width
                    height: 70
                    readonly property real mid: width / 2
                    Rectangle {
                        x: 0; y: 30; width: parent.width; height: 6; radius: 3
                        color: Theme.button
                    }
                    Rectangle {
                        x: parent.mid - width / 2; y: 24; width: parent.width * 0.1; height: 18; radius: 4
                        color: Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.25)
                    }
                    Repeater {
                        model: [-50, -25, 0, 25, 50]
                        Text {
                            required property int modelData
                            x: parent.mid + modelData / 50 * (parent.width / 2 - 14) - width / 2
                            y: 48
                            text: (modelData > 0 ? "+" : "") + modelData
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                    Rectangle {
                        visible: page.refMidi >= 0
                        width: 6; height: 44; radius: 3
                        y: 11
                        x: parent.mid + Math.max(-50, Math.min(50, page.cents)) / 50 * (parent.width / 2 - 14) - width / 2
                        color: page.inTune ? Theme.success : Theme.accent
                        Behavior on x { NumberAnimation { duration: 90 } }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.refMidi < 0 ? " " : page.inTune ? "Afinado!"
                         : page.cents < 0 ? "Baixo: aperte a tarraxa (" + Math.round(page.cents) + " cents)"
                                          : "Alto: afrouxe a tarraxa (+" + Math.round(page.cents) + " cents)"
                    color: page.inTune ? Theme.success : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }

                // Cordas: automático ou uma fixa.
                Column {
                    width: parent.width
                    spacing: 8
                    Text {
                        text: "Corda (afinação padrão)"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        AppButton {
                            text: "Automático"
                            suggested: page.target < 0
                            onClicked: page.target = -1
                        }
                        Repeater {
                            model: 6
                            AppButton {
                                required property int index
                                text: page.stringNames[index] + (page.target < 0 && page.nearString === index ? " ●" : "")
                                suggested: page.target === index
                                onClicked: page.target = page.target === index ? -1 : index
                            }
                        }
                    }
                }

                // Volume que chega do microfone.
                Column {
                    visible: mic.active
                    width: parent.width
                    spacing: 4
                    Text {
                        text: "Volume do microfone"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Rectangle {
                        width: parent.width; height: 8; radius: 4
                        color: Theme.button
                        Rectangle {
                            width: parent.width * Math.min(1, mic.level * 8); height: parent.height; radius: 4
                            color: Theme.accent
                        }
                    }
                }
            }
        }
    }
}
