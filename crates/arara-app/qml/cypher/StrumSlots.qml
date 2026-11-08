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
    function toggleAccent(i) {
        var c = strum.pattern[i]
        if (!c) return
        strum.pattern[i] = Examples.withAccent(c, !Examples.isAccent(c))
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
            readonly property bool strong: Examples.isAccent(modelData)
            color: modelData === "" ? Theme.button
                 : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, strong ? 0.32 : 0.18)
            border.width: strong ? 2 : 0
            border.color: Theme.accent
            Column {
                anchors.centerIn: parent
                spacing: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Examples.strokeArrow(slot.modelData)
                    color: slot.modelData === "" || Examples.isMute(slot.modelData) ? Theme.textDim : Theme.accent
                    font.pixelSize: slot.strong ? 26 : 22
                    font.weight: slot.strong ? Font.Black : Font.Bold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: slot.modelData === "" ? " " : Examples.strokeLabel(Examples.plain(slot.modelData))
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
            // Clique troca o golpe (mantendo o "forte"); clique direito ou o ">"
            // no canto liga e desliga a palhetada forte.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (e) => {
                    if (e.button === Qt.RightButton) { root.toggleAccent(slot.index); return }
                    var i = root.codes.indexOf(Examples.plain(slot.modelData))
                    var next = root.codes[(i + 1) % root.codes.length]
                    root.strum.pattern[slot.index] = Examples.withAccent(next, slot.strong)
                    root.changed()
                }
            }
            Rectangle {
                visible: slot.modelData !== ""
                anchors { right: parent.right; top: parent.top; margins: 2 }
                width: 16; height: 16; radius: 8
                color: slot.strong ? Theme.accent : (accMouse.containsMouse ? Theme.buttonHover : "transparent")
                Text {
                    anchors.centerIn: parent
                    text: ">"
                    color: slot.strong ? Theme.accentFg : Theme.textDim
                    font.pixelSize: 11; font.bold: true
                }
                MouseArea { id: accMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleAccent(slot.index) }
            }
        }
    }
}
}
