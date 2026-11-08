import QtQuick
import QtQuick.Controls.Basic
import AraraCypher

// Campo de texto de várias linhas (cifra colada, tablatura), em fonte de
// largura fixa para as colunas da tab ficarem alinhadas.
TextArea {
    id: area
    color: Theme.text
    placeholderTextColor: Theme.textDim
    selectionColor: Theme.accent
    selectedTextColor: Theme.selectionFg
    font.family: Theme.monoFamily
    font.pixelSize: Theme.fontSize
    selectByMouse: true
    wrapMode: TextEdit.NoWrap
    padding: 10
    background: Rectangle {
        implicitHeight: 100
        radius: Theme.radiusSmall
        color: Theme.apple ? Theme.window : Theme.button
        border.width: area.activeFocus ? 2 : 0
        border.color: Theme.accent
    }
}
