import QtQuick
import AraraCypher

// Cabeçalho da página.
// GNOME: barra de título com o nome centralizado e uma linha embaixo.
// Apple: título grande e em negrito, alinhado à esquerda, sem barra.
Rectangle {
    id: root
    property string title
    default property alias actions: actionRow.data

    implicitHeight: Theme.apple ? 64 : 47
    color: Theme.headerBar

    Rectangle {
        visible: !Theme.apple
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.dark ? Qt.rgba(0, 0, 0, 0.36) : Qt.rgba(0, 0, 0, 0.12)
    }

    // Título: centralizado no GNOME quando cabe; senão encosta à esquerda e
    // corta com "…" antes dos botões, sem nunca ficar por baixo deles.
    Text {
        id: titleText
        readonly property real room: actionRow.x - 12 - Theme.pagePadding
        text: root.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.titleSize
        font.weight: Theme.titleWeight
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: Theme.apple ? 6 : 0
        width: Math.max(0, Math.min(implicitWidth, room))
        x: Theme.apple ? Theme.pagePadding
                       : Math.max(Theme.pagePadding, Math.min((parent.width - width) / 2, actionRow.x - 12 - width))
    }

    Row {
        id: actionRow
        spacing: 6
        anchors.right: parent.right
        anchors.rightMargin: Theme.apple ? Theme.pagePadding : 8
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: Theme.apple ? 6 : 0
    }
}
