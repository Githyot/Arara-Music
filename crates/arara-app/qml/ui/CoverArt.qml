import QtQuick
import AraraStyle

// Album/track art as a rounded square (anti-aliased shader mask, since Qt Quick
// only clips to square bounds), with a placeholder note when there is none.
Item {
    id: art
    property string source: ""
    property int decode: Math.max(width, height)
    property int iconSize: Math.max(16, Math.round(width * 0.4))
    property real radius: Math.max(3, Math.round(width * Theme.coverRound))
    property bool hovered: false

    Rectangle {
        anchors.fill: parent
        radius: art.radius
        color: Theme.dark ? "#3a3a3e" : "#e6e6e9"
        visible: img.status !== Image.Ready
    }
    Image {
        id: img
        anchors.fill: parent
        source: art.source
        sourceSize: Qt.size(art.decode, art.decode)
        asynchronous: true; cache: false
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    ShaderEffect {
        anchors.fill: parent
        visible: img.status === Image.Ready
        property variant src: img
        property size size: Qt.size(width, height)
        property real radius: art.radius
        fragmentShader: "qrc:/qt/qml/AraraStyle/rounded.frag.qsb"
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }
    Rectangle { anchors.fill: parent; radius: art.radius; color: "white"; opacity: art.hovered ? 0.08 : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
    Icon {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        name: "note"; size: art.iconSize; color: Theme.dimFg
    }
}
