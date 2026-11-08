import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import AraraCypher

// Aba Estudos do Arara Music: o Arara Cypher inteiro (cifras, editor,
// afinador e estudo). As abas ficam numa barra em cima, como o
// AdwViewSwitcher do GNOME; a barra lateral é a do próprio Arara.
Rectangle {
    id: studies
    color: Theme.window
    property int currentPage: 0
    // Uma música da biblioteca do Arara pediu uma cifra nova (título e artista já preenchidos).
    function newSheetFor(title, artist) {
        editorPage.load(null)
        editorPage.draft.title = title || ""
        editorPage.draft.artist = artist || ""
        editorPage.bump()
        currentPage = 1
    }
    function openSheet(song) { libraryPage.showSong(song); currentPage = 0 }
    function editSheet(song) { editorPage.load(song); currentPage = 1 }

    readonly property var pages: [
        { icon: "library",  label: "Cifras" },
        { icon: "edit",     label: "Editor" },
        { icon: "tuner",    label: "Afinador" },
        { icon: "study",    label: "Estudo" },
        { icon: "settings", label: "Ajustes" }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Abas ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            color: Theme.headerBar
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.36) : Qt.rgba(0, 0, 0, 0.12)
            }
            Row {
                anchors.centerIn: parent
                spacing: 4
                Repeater {
                    model: studies.pages
                    Rectangle {
                        id: tab
                        required property var modelData
                        required property int index
                        readonly property bool selected: studies.currentPage === index
                        readonly property bool iconOnly: studies.width < 620
                        width: iconOnly ? 44 : tabRow.implicitWidth + 28
                        height: 34
                        radius: Theme.radiusSmall
                        color: selected ? Theme.selection
                             : tabMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06) : "transparent"
                        Row {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 8
                            Icon { name: tab.modelData.icon; size: 16; color: tab.selected ? Theme.selectionFg : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                visible: !tab.iconOnly
                                text: tab.modelData.label
                                color: tab.selected ? Theme.selectionFg : Theme.text
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                font.weight: tab.selected ? Font.DemiBold : Font.Normal
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: studies.currentPage = tab.index }
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: studies.currentPage

            LibraryPage {
                id: libraryPage
                onRequestPage: (i) => studies.currentPage = i
                onNewSong: { editorPage.load(null); studies.currentPage = 1 }
                onEditSong: (song) => { editorPage.load(song); studies.currentPage = 1 }
            }
            EditorPage {
                id: editorPage
                onSaved: (song) => { libraryPage.showSong(song); studies.currentPage = 0 }
                onClosed: studies.currentPage = 0
            }
            TunerPage {}
            StudyPage {}
            SettingsPage {}
        }
    }
}
