import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import AraraCypher
import io.github.arara as Arara

// Lista das cifras. Por enquanto mostra as músicas de exemplo; a biblioteca
// salva no aparelho chega no passo 2 junto com o editor.
Rectangle {
    id: page
    signal requestPage(int index)
    signal editSong(var song)
    signal newSong()
    property var openSong: null

    readonly property var mySongs: {
        Arara.CypherLibrary.revision
        return JSON.parse(Arara.CypherLibrary.songs())
    }

    // Abre uma música salva pelo id (depois de salvar no editor).
    function showSong(song) {
        openSong = null
        openSong = song
    }
    color: Theme.window

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        visible: page.openSong === null

        HeaderBar {
            Layout.fillWidth: true
            title: "Biblioteca"
            AppButton {
                iconName: "add"
                flat: true
                onClicked: page.newSong()
            }
        }

        Flickable {

            ScrollBar.vertical: AppScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: list.implicitHeight + 2 * Theme.pagePadding
            clip: true

            Column {
                id: list
                y: Theme.pagePadding
                width: Math.min(parent.width - 2 * Theme.pagePadding, 720)
                x: (parent.width - width) / 2
                spacing: 8

                Repeater {
                    model: [{ title: "Minhas cifras", songs: page.mySongs },
                            { title: "Exemplos", songs: Examples.songs }]
                    Column {
                        id: group
                        required property var modelData
                        width: list.width
                        spacing: 8
                        visible: modelData.songs.length > 0
                SectionTitle { text: group.modelData.title }

                Repeater {
                    model: group.modelData.songs
                    Card {
                        id: songCard
                        required property var modelData
                        width: list.width
                        padding: 12

                        RowLayout {
                            width: parent.width
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 44
                                radius: Theme.radiusSmall + 2
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                Icon {
                                    anchors.centerIn: parent
                                    name: "note"
                                    size: 20
                                    color: Theme.accent
                                }
                            }
                            Column {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: songCard.modelData.title
                                    color: Theme.text
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize + 1
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    text: (songCard.modelData.artist || "Sem artista") + " · Tom " + (songCard.modelData.key || "?")
                                      + (songCard.modelData.capo ? " · Capo " + songCard.modelData.capo + "ª" : "")
                                    color: Theme.textDim
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }
                            }
                            Text {
                                text: "›"
                                color: Theme.textDim
                                font.pixelSize: 24
                            }
                        }

                        MouseArea {
                            parent: songCard
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.openSong = songCard.modelData
                        }
                    }
                }
                    }
                }

                Item { width: 1; height: 16 }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.mySongs.length === 0
                    text: "Toque em + para escrever uma cifra, colar uma do site ou importar de um print. Elas ficam salvas só no seu computador."
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: page.openSong !== null
        sourceComponent: SongPage {
            song: page.openSong
            onBack: page.openSong = null
            onEdit: page.editSong(page.openSong)
        }
    }
}
