import QtQuick

// Adwaita symbolic icon, tinted to `color` (defaults to the foreground color).
Item {
    id: icon
    property string name: ""
    property color color: Theme.fg
    property int size: 16
    implicitWidth: size; implicitHeight: size

    Image {
        id: img
        anchors.fill: parent
        source: icon.name ? "qrc:/qt/qml/AraraStyle/icons/" + icon.name + ".svg" : ""
        sourceSize: Qt.size(icon.size * 2, icon.size * 2)   // crisp on HiDPI
        visible: false
        smooth: true
    }
    ShaderEffect {
        anchors.fill: parent
        visible: img.status === Image.Ready
        property variant src: img
        property color color: icon.color
        fragmentShader: "qrc:/qt/qml/AraraStyle/tint.frag.qsb"
    }
}
