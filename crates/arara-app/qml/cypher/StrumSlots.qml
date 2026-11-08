import QtQuick
import AraraCypher

// Os tempos de uma batida, um botão por tempo: tocar troca o golpe
// (pausa, baixo, tudo, acorde, agudas, abafa). Em cima, quantos tempos a
// batida tem (qualquer número) e a divisão: colcheia, tercina, semicolcheia.
Column {
    id: root
    property var strum: null
    property real slotW: 52
    property int rev: 0               // muda a cada edição (o padrão é mexido no lugar)
    signal changed()

    readonly property var codes: ["", "B", "D", "d", "U", "X", "XU"]
    readonly property var codeLabel: ({ "": "·", "B": "baixo", "D": "tudo", "d": "acorde", "U": "agudas", "X": "abafa ↓", "XU": "abafa ↑" })

    spacing: 6
    readonly property int per: rev, !strum ? 2 : strum.per ? strum.per
                                : strum.counts && strum.counts.indexOf("&") >= 0 ? 4
                                : strum.counts && strum.counts.indexOf("a") >= 0 ? 3 : 2
    function resize(n) {
        n = Math.max(1, Math.min(48, n))
        while (strum.pattern.length < n) strum.pattern.push("")
        strum.pattern.length = n
        strum.counts = Examples.countsFor(n, per)
        changed()
    }
    function setPer(p) {
        strum.per = p
        strum.counts = Examples.countsFor(strum.pattern.length, p)
        changed()
    }

    Flow {
        width: parent.width
        spacing: 6
        Text {
            height: Theme.controlHeight
            verticalAlignment: Text.AlignVCenter
            text: root.rev, root.strum ? root.strum.pattern.length + " toques" : ""
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        AppButton { text: "−1"; enabled: !!root.strum && root.strum.pattern.length > 1; onClicked: root.resize(root.strum.pattern.length - 1) }
        AppButton { text: "+1"; enabled: !!root.strum; onClicked: root.resize(root.strum.pattern.length + 1) }
        AppButton { text: "+1 compasso"; flat: true; enabled: !!root.strum; onClicked: root.resize(root.strum.pattern.length + root.per * 4) }
        SegmentedControl {
            model: [{ value: "2", label: "1 e" }, { value: "3", label: "Tercina" }, { value: "4", label: "1 e & a" }]
            current: String(root.per)
            onActivated: (v) => root.setPer(Number(v))
        }
    }

    Flow {
    width: parent.width
    spacing: 4
    Repeater {
        model: root.rev, root.strum ? root.strum.pattern.slice() : []
        Rectangle {
            id: slot
            required property string modelData
            required property int index
            width: root.slotW
            height: 62
            radius: Theme.radiusSmall
            color: modelData === "" ? Theme.button
                 : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
            Column {
                anchors.centerIn: parent
                spacing: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Examples.strokeArrow(slot.modelData)
                    color: slot.modelData === "" || Examples.isMute(slot.modelData) ? Theme.textDim : Theme.accent
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: slot.modelData === "" ? " " : Examples.strokeLabel(slot.modelData)
                    width: Math.min(implicitWidth, root.slotW - 4)
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.strum.counts[slot.index] || ""
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var i = root.codes.indexOf(slot.modelData)
                    root.strum.pattern[slot.index] = root.codes[(i + 1) % root.codes.length]
                    root.changed()
                }
            }
        }
    }
}
}
