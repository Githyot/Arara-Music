import QtQuick
import QtQuick.Controls
import AraraStyle

// Playback speed popover (GtkPopover look): any value from 0.25× to 2×
// in 0.01 steps, − / + buttons for 5% nudges and quick presets.
Popup {
    id: pop
    width: 300
    padding: 14
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    readonly property real rate: Prefs.playbackRate
    readonly property var presets: [0.5, 0.75, 1, 1.25, 1.5, 2]
    function set(r) { Prefs.requestRate(r) }

    // Open just above (or below, if there is no room) the given item.
    function openFor(item) {
        var host = item.Window.contentItem
        parent = host
        var p = item.mapToItem(host, item.width / 2, 0)
        x = Math.max(8, Math.min(host.width - width - 8, p.x - width / 2))
        var above = p.y - implicitHeight - 8
        y = above > 8 ? above : p.y + item.height + 8
        open()
    }

    background: Rectangle {
        radius: Theme.popupRadius
        color: Theme.popupBg
        border.color: Theme.border
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -2; radius: parent.radius + 2; color: "#000000"; opacity: 0.08 }
    }

    contentItem: Column {
        spacing: 12

        Item {
            width: parent.width; height: valueText.height
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Velocidade"
                color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
            }
            Text {
                id: valueText
                anchors.right: parent.right
                text: Prefs.rateLabel(pop.rate)
                color: Math.abs(pop.rate - 1) < 0.001 ? Theme.fg : Theme.accentFg
                font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 2; font.weight: Font.Bold
            }
        }

        Row {
            width: parent.width
            spacing: 6
            FlatButton {
                id: minus
                anchors.verticalCenter: parent.verticalCenter
                text: "−"; circular: true; size: 30
                tip: "Mais devagar  ["
                onClicked: pop.set(pop.rate - 0.05)
            }
            ThemedSlider {
                id: slider
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - minus.width - plus.width - 12
                from: Prefs.minRate; to: Prefs.maxRate; stepSize: 0.01
                snapMode: Slider.SnapAlways
                value: pressed ? value : pop.rate
                // A small pull towards 1× so "normal" is easy to land on.
                onMoved: pop.set(Math.abs(value - 1) < 0.03 ? 1 : value)
                WheelHandler { onWheel: (e) => pop.set(pop.rate + (e.angleDelta.y > 0 ? 0.05 : -0.05)) }
            }
            FlatButton {
                id: plus
                anchors.verticalCenter: parent.verticalCenter
                text: "+"; circular: true; size: 30
                tip: "Mais rápido  ]"
                onClicked: pop.set(pop.rate + 0.05)
            }
        }

        // Scale under the slider: 0,25× · 1× · 2×, 1× placed where it really is.
        Item {
            width: parent.width; height: lo.height
            readonly property real x0: minus.width + 6 + slider.leftPadding
            readonly property real span: slider.availableWidth
            Text { id: lo; x: parent.x0 - width / 2; text: "0,25×"; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
            Text { x: parent.x0 + parent.span * (1 - Prefs.minRate) / (Prefs.maxRate - Prefs.minRate) - width / 2; text: "1×"; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
            Text { x: parent.x0 + parent.span - width / 2; text: "2×"; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
        }

        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: pop.presets
                Rectangle {
                    id: chip
                    required property real modelData
                    readonly property bool on: Math.abs(pop.rate - modelData) < 0.001
                    width: (pop.availableWidth - 5 * 6) / 6; height: 30
                    radius: Theme.material ? height / 2 : Theme.radius
                    color: on ? Theme.accent : chipMa.containsMouse ? Theme.pressed : Theme.hover
                    Text {
                        anchors.centerIn: parent
                        text: Prefs.rateLabel(chip.modelData)
                        color: chip.on ? Theme.accentInk : Theme.fg
                        font.family: Theme.font; font.pointSize: Theme.fontSize - 1; font.weight: Font.DemiBold
                    }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pop.set(chip.modelData) }
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: (Prefs.pitchKept ? "O tom da voz é mantido e a letra acompanha a velocidade."
                                   : "A letra acompanha a velocidade. Com o Qt instalado (anterior ao 6.10), a voz fica mais aguda ou mais grave.")
                  + "\nAtalhos: [ e ] mudam 5%, \\ volta ao normal."
            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2
        }
    }
}
