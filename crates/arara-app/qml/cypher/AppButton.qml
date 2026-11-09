import QtQuick
import QtQuick.Controls.Basic
import AraraCypher

// Botão nos dois estilos: GNOME (cantos de 6px, cinza) e Apple (pílula).
// `suggested` usa a cor de destaque, como o "suggested-action" do GNOME.
Button {
    id: control
    property bool suggested: false
    property string iconName: ""

    implicitHeight: Theme.controlHeight
    implicitWidth: Math.max(implicitHeight, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: text.length > 0 ? (Theme.pillButtons ? 18 : 14) : 8
    rightPadding: leftPadding
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    font.weight: Theme.apple ? Font.DemiBold : Font.Bold

    readonly property color _fg: suggested ? Theme.accentFg
                                           : (Theme.apple ? Theme.accent : Theme.text)

    contentItem: Row {
        spacing: 6
        anchors.centerIn: parent
        Icon {
            visible: control.iconName.length > 0
            name: control.iconName
            color: control._fg
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: control.text.length > 0
            text: control.text
            font: control.font
            color: control._fg
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: Theme.pillButtons ? height / 2 : Theme.radiusSmall
        color: {
            if (control.suggested)
                return control.down ? Qt.darker(Theme.accentBg, 1.15)
                     : control.hovered ? Qt.lighter(Theme.accentBg, 1.08) : Theme.accentBg
            if (control.flat)
                return control.down ? Theme.button
                     : control.hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.07)
                     : "transparent"
            return control.down ? Qt.darker(Theme.button, 1.1)
                 : control.hovered ? Theme.buttonHover : Theme.button
        }
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
