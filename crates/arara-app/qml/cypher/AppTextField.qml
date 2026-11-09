import QtQuick
import QtQuick.Controls.Basic
import AraraCypher

// Campo de texto de uma linha nos dois estilos.
TextField {
    id: field
    property bool mono: false
    color: Theme.text
    placeholderTextColor: Theme.textDim
    selectionColor: Theme.accent
    selectedTextColor: Theme.selectionFg
    font.family: mono ? Theme.monoFamily : Theme.fontFamily
    font.pixelSize: Theme.fontSize + (mono ? 1 : 0)
    selectByMouse: true
    padding: 9
    background: Rectangle {
        implicitHeight: Theme.controlHeight
        radius: Theme.radiusSmall
        color: Theme.apple ? Theme.window : Theme.button
        border.width: field.activeFocus ? 2 : 0
        border.color: Theme.accent
    }
}
