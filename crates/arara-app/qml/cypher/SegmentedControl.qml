import QtQuick
import AraraCypher

// Escolha entre poucas opções: grupo de botões "linked" no GNOME,
// controle segmentado na Apple.
Rectangle {
    id: root
    property var model: []          // [{ value, label }]
    property string current: ""
    signal activated(string value)

    implicitHeight: Theme.controlHeight
    implicitWidth: row.implicitWidth + 4
    radius: Theme.apple ? 9 : Theme.radiusSmall
    color: Theme.button

    Row {
        id: row
        x: 2
        y: 2
        height: parent.height - 4
        spacing: Theme.apple ? 0 : 2

        Repeater {
            model: root.model
            delegate: Rectangle {
                id: seg
                required property var modelData
                readonly property bool selected: root.current === modelData.value
                width: label.implicitWidth + 28
                height: row.height
                radius: Theme.apple ? 7 : Theme.radiusSmall - 1
                color: selected ? (Theme.apple ? (Theme.dark ? "#636366" : "#ffffff")
                                               : Theme.accentBg)
                                : mouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                                                      : "transparent"
                border.width: Theme.apple && selected && !Theme.dark ? 0.5 : 0
                border.color: Qt.rgba(0, 0, 0, 0.08)
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: seg.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.apple ? 13 : Theme.fontSize
                    font.weight: seg.selected ? Font.DemiBold : Font.Normal
                    color: seg.selected && !Theme.apple ? Theme.accentFg : Theme.text
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activated(seg.modelData.value)
                }
            }
        }
    }
}
