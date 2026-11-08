import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import AraraCypher
import io.github.arara as Arara

Rectangle {
    color: Theme.window

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        HeaderBar { Layout.fillWidth: true; title: "Ajustes" }

        Flickable {

            ScrollBar.vertical: AppScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: content.implicitHeight + 2 * Theme.pagePadding
            clip: true

            Column {
                id: content
                y: Theme.pagePadding
                width: Math.min(parent.width - 2 * Theme.pagePadding, 560)
                x: (parent.width - width) / 2
                spacing: 8

                SectionTitle { text: "Aparência" }

                Card {
                    width: parent.width
                    // Dentro do Arara Music o visual vem das Preferências do Arara.
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "O estilo (GNOME ou Apple) e o claro/escuro seguem as Preferências do Arara Music."
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }

                Item { width: 1; height: 12 }
                SectionTitle { text: "Exemplos" }

                Card {
                    width: parent.width
                    RowLayout {
                        width: parent.width
                        spacing: 12
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: Examples.hidden.length === 0
                                  ? "Todas as cifras de exemplo estão na lista. Dá para excluir uma pelo ícone de lixeira em Cifras."
                                  : Examples.hidden.length + (Examples.hidden.length === 1 ? " exemplo excluído." : " exemplos excluídos.")
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        AppButton {
                            text: "Restaurar exemplos"
                            enabled: Examples.hidden.length > 0
                            onClicked: Examples.restoreExamples()
                        }
                    }
                }

                Item { width: 1; height: 12 }
                SectionTitle { text: "Sobre" }

                Card {
                    width: parent.width
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: "Versão"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            text: Arara.CypherMusic.version
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }
                }
            }
        }
    }
}
