import QtQuick
import AraraCypher

// Item de navegação. `vertical` = aba da barra inferior (celular);
// senão é uma linha da barra lateral (computador).
Item {
    id: root
    property string iconName
    property string label
    property bool selected: false
    property bool vertical: false
    signal clicked()

    implicitHeight: vertical ? 54 : 38
    implicitWidth: vertical ? 72 : 200

    readonly property color _fg: {
        if (vertical)
            return selected ? Theme.accent : Theme.textDim
        return selected ? Theme.selectionFg : Theme.text
    }

    Rectangle {
        visible: !root.vertical || !Theme.apple
        anchors.fill: parent
        anchors.margins: root.vertical ? 6 : 0
        radius: root.vertical ? height / 2 : Theme.radiusSmall
        color: root.vertical
               ? (root.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : "transparent")
               : root.selected ? Theme.selection
               : mouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
               : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // Linha (barra lateral)
    Row {
        visible: !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        spacing: 12
        Icon {
            name: root.iconName
            color: root._fg
            size: 16
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.label
            color: root._fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: root.selected && Theme.apple ? Font.DemiBold : Font.Normal
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Coluna (aba inferior)
    Column {
        visible: root.vertical
        anchors.centerIn: parent
        spacing: 3
        Icon {
            name: root.iconName
            color: root._fg
            size: 20
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: root.label
            color: root._fg
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
