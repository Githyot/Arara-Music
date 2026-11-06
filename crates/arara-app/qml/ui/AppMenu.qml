import QtQuick
import QtQuick.Controls
import AraraStyle

// Primary menu (the "☰" of GNOME apps). Settings live in Preferências;
// the menu keeps only actions.
Popup {
    id: menu
    signal chooseFolder()
    signal rescan()
    signal importPlaylists()
    signal shortcuts()
    signal preferences()
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
        radius: Theme.popupRadius
        color: Theme.popupBg
        border.color: Theme.border
    }

    component Entry: Rectangle {
        property string label: ""
        property bool check: false
        property bool checked: false
        property string shortcut: ""
        signal triggered()
        width: menu.width - 12; height: 34; radius: Theme.material ? 0 : Theme.radius
        color: em.containsMouse ? Theme.hover : "transparent"
        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: parent.label; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
        Text { visible: parent.shortcut !== "" && !parent.check; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: parent.shortcut; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
        Icon { visible: parent.check && parent.checked; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } name: "check"; size: 16 }
        MouseArea { id: em; anchors.fill: parent; hoverEnabled: true; onClicked: parent.triggered() }
    }
    component Sep: Rectangle { width: menu.width - 12; height: 1; color: Theme.border; opacity: 0.6 }

    contentItem: Column {
        Entry { label: "Preferências…"; shortcut: "Ctrl+,"; onTriggered: { menu.close(); menu.preferences() } }
        Sep {}
        Entry { label: "Pastas de música…"; onTriggered: { menu.close(); menu.chooseFolder() } }
        Entry { label: "Reindexar agora"; onTriggered: { menu.close(); menu.rescan() } }
        Entry { label: "Importar playlists e curtidas…"; onTriggered: { menu.close(); menu.importPlaylists() } }
        Sep {}
        Entry { label: "Atalhos de teclado"; shortcut: "Ctrl+?"; onTriggered: { menu.close(); menu.shortcuts() } }
        Entry { label: "Sobre o Arara Music"; onTriggered: { menu.close(); menu.about() } }
    }
}
