import QtQuick
import QtQuick.Controls
import AraraStyle

// Primary menu (the "☰" of GNOME apps): library folder, rescan, import,
// volume normalization, shortcuts, about.
Popup {
    id: menu
    property bool replayGain: true
    signal chooseFolder()
    signal rescan()
    signal importPlaylists()
    signal toggleReplayGain()
    signal shortcuts()
    signal about()

    width: 300
    padding: 6
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function openUnder(item) {
        var p = item.mapToItem(null, item.width, item.height + 4)
        menu.x = Math.max(8, p.x - width)
        menu.y = p.y
        open()
    }

    background: Rectangle {
        radius: Theme.cardRadius
        color: Theme.dark ? "#36363a" : "#ffffff"
        border.color: Theme.border
    }

    component Entry: Rectangle {
        property string label: ""
        property bool check: false
        property bool checked: false
        signal triggered()
        width: menu.width - 12; height: 34; radius: Theme.radius
        color: em.containsMouse ? Theme.hover : "transparent"
        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: parent.label; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
        Icon { visible: parent.check && parent.checked; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } name: "check"; size: 16 }
        MouseArea { id: em; anchors.fill: parent; hoverEnabled: true; onClicked: parent.triggered() }
    }
    component Sep: Rectangle { width: menu.width - 12; height: 1; color: Theme.border; opacity: 0.6 }

    contentItem: Column {
        Entry { label: "Pasta de músicas…"; onTriggered: { menu.close(); menu.chooseFolder() } }
        Entry { label: "Reindexar agora"; onTriggered: { menu.close(); menu.rescan() } }
        Entry { label: "Importar playlists e curtidas…"; onTriggered: { menu.close(); menu.importPlaylists() } }
        Sep {}
        Entry { label: "Normalizar volume (ReplayGain)"; check: true; checked: menu.replayGain; onTriggered: menu.toggleReplayGain() }
        Sep {}
        Entry { label: "Atalhos de teclado"; onTriggered: { menu.close(); menu.shortcuts() } }
        Entry { label: "Sobre o Arara Music"; onTriggered: { menu.close(); menu.about() } }
    }
}
