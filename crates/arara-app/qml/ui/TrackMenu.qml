import QtQuick
import QtQuick.Controls
import AraraStyle

// Popover menu for a track (GtkPopoverMenu look): queue actions, playlists, go to album.
Popup {
    id: menu
    property var track: null
    property var playlists: []
    property bool showPlaylists: false
    signal playNext(var track)
    signal enqueue(var track)
    signal addToPlaylist(var track, int playlistId)
    signal newPlaylistWith(var track)
    signal goToAlbum(var track)

    width: 240
    padding: 6
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: showPlaylists = false

    function openAt(t, x, y, lists) {
        track = t; playlists = lists; showPlaylists = false
        menu.x = Math.min(x, parent.width - width - 8)
        menu.y = Math.min(y, parent.height - 260)
        open()
    }

    background: Rectangle {
        radius: Theme.cardRadius
        color: Theme.dark ? "#36363a" : "#ffffff"
        border.color: Theme.border
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -2; radius: parent.radius + 2; color: "#000000"; opacity: 0.08 }
    }

    component Item_: Rectangle {
        property string label: ""
        property bool submenu: false
        signal triggered()
        width: menu.width - 12; height: 34; radius: Theme.radius
        color: im.containsMouse ? Theme.hover : "transparent"
        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: parent.label; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
        Text { visible: parent.submenu; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: "›"; color: Theme.dimFg; font.pointSize: Theme.fontSize + 2 }
        MouseArea { id: im; anchors.fill: parent; hoverEnabled: true; onClicked: parent.triggered() }
    }

    contentItem: Column {
        spacing: 0
        Column {
            visible: !menu.showPlaylists
            Item_ { label: "Tocar a seguir"; onTriggered: { menu.playNext(menu.track); menu.close() } }
            Item_ { label: "Adicionar à fila"; onTriggered: { menu.enqueue(menu.track); menu.close() } }
            Item_ { label: "Adicionar à playlist"; submenu: true; onTriggered: menu.showPlaylists = true }
            Rectangle { width: menu.width - 12; height: 1; color: Theme.border; opacity: 0.6 }
            Item_ { label: "Ir para o álbum"; visible: menu.track && menu.track.albumId; onTriggered: { menu.goToAlbum(menu.track); menu.close() } }
        }
        Column {
            visible: menu.showPlaylists
            Item_ { label: "‹  Voltar"; onTriggered: menu.showPlaylists = false }
            Rectangle { width: menu.width - 12; height: 1; color: Theme.border; opacity: 0.6 }
            Repeater {
                model: menu.playlists
                Item_ {
                    required property var modelData
                    label: modelData.name
                    onTriggered: { menu.addToPlaylist(menu.track, modelData.id); menu.close() }
                }
            }
            Item_ { label: "Nova playlist…"; onTriggered: { menu.newPlaylistWith(menu.track); menu.close() } }
        }
    }
}
