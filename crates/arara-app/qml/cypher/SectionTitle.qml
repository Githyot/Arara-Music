import QtQuick
import AraraCypher

// Título de um grupo de opções. Na Apple fica em caixa alta e cinza.
Text {
    font.family: Theme.fontFamily
    font.pixelSize: Theme.apple ? 13 : Theme.fontSize
    font.weight: Theme.apple ? Font.Normal : Font.Bold
    font.capitalization: Theme.apple ? Font.AllUppercase : Font.MixedCase
    color: Theme.apple ? Theme.textDim : Theme.text
    leftPadding: Theme.apple ? 14 : 2
}
