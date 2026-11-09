import QtQuick
import AraraCypher

// Estado vazio: ícone grande, título e descrição, como o AdwStatusPage.
Column {
    id: root
    property string iconName
    property string title
    property string description
    default property alias extra: extraItems.data

    spacing: 10
    width: Math.min(parent ? parent.width - 2 * Theme.pagePadding : 360, 420)

    Icon {
        name: root.iconName
        size: 64
        color: Theme.apple ? Theme.accent : Theme.textDim
        opacity: Theme.apple ? 1 : 0.55
        anchors.horizontalCenter: parent.horizontalCenter
    }
    Item { width: 1; height: 8 }
    Text {
        text: root.title
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.apple ? 22 : 24
        font.weight: Font.Bold
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        width: parent.width
    }
    Text {
        text: root.description
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        width: parent.width
        lineHeight: 1.2
    }
    Item { width: 1; height: 8 }
    Column {
        id: extraItems
        spacing: 10
        anchors.horizontalCenter: parent.horizontalCenter
    }
}
