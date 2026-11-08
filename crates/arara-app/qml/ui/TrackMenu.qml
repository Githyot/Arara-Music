import QtQuick
import QtQuick.Controls
import AraraStyle

// Popover menu for a track (GtkPopoverMenu look). Quick actions on top
// (favorite, share), then queue, playlists, station, navigation, info,
// lyrics and file actions, grouped by separators.
Popup {
    id: menu
    property var track: null
    property var playlists: []
    property bool showPlaylists: false
    // Hide "Ir para…" entries already on screen (e.g. the album page itself).
    property bool hasLyrics: true
    signal playNext(var track)
    signal enqueue(var track)
    signal addToPlaylist(var track, int playlistId)
    signal newPlaylistWith(var track)
    signal goToAlbum(var track)
    signal goToArtist(var track)
    signal toggleStar(var track)
    signal share(var track)
    signal startStation(var track)
    signal showInfo(var track)
    signal editInfo(var track)
    signal showLyrics(var track)
    signal copyLyrics(var track)
    signal editLyrics(var track)
    signal showInFolder(var track)
    signal toggleExplicit(var track, bool shown)
    // A/B loop: id of the song whose part is repeating now (-1 = none).
    property int loopingId: -1
    signal loopSection(var track)
    // Is the E badge showing for this track right now?
    readonly property bool explicitShown: {
        if (!track) return false
        var o = Prefs.explicitOverride, k = o[Number(track.id)] !== undefined ? o[Number(track.id)] : Number(track.explicit || 0)
        return k === 1 || (k === 2 && Prefs.explicitLyrics)
    }

    width: 272
    padding: 6
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: showPlaylists = false

    readonly property bool isLocal: !!track && !track.remote
    readonly property real wantedHeight: (showPlaylists ? lists.implicitHeight : main.implicitHeight) + 12

    function place(x, y) {
        var h = Math.min(wantedHeight, parent.height - 16)
        menu.x = Math.max(8, Math.min(x, parent.width - width - 8))
        menu.y = Math.max(8, Math.min(y, parent.height - h - 8))
    }
    function openAt(t, x, y, lists) {
        track = t; playlists = lists; showPlaylists = false
        open(); place(x, y)
    }

    // Straight to the "add to playlist" list (button in the lyrics screen).
    function openPlaylistsAt(t, x, y, lists) {
        track = t; playlists = lists; showPlaylists = true
        open(); place(x, y)
    }
    onShowPlaylistsChanged: if (visible) place(x, y)

    height: Math.min(wantedHeight, parent ? parent.height - 16 : wantedHeight)

    background: Rectangle {
        radius: Theme.popupRadius
        color: Theme.popupBg
        border.color: Theme.border
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -2; radius: parent.radius + 2; color: "#000000"; opacity: 0.08 }
    }

    component Sep: Rectangle { width: menu.width - 12; height: 9; color: "transparent"
        Rectangle { anchors.centerIn: parent; width: parent.width - 8; height: 1; color: Theme.border; opacity: 0.7 } }

    component Item_: Rectangle {
        id: it
        property string label: ""
        property string sub: ""
        property string icon: ""
        property bool submenu: false
        signal triggered()
        width: menu.width - 12; height: sub !== "" ? 46 : 34; radius: Theme.material ? 0 : Theme.radius
        color: im.containsMouse ? Theme.hover : "transparent"
        Icon {
            id: ic
            visible: it.icon !== ""
            name: it.icon; size: 16; color: Theme.fg
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
        }
        Column {
            anchors { left: parent.left; leftMargin: it.icon !== "" ? 36 : 12; right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
            Text { width: parent.width; elide: Text.ElideRight; text: it.label; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
            Text { visible: it.sub !== ""; width: parent.width; elide: Text.ElideRight; text: it.sub; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5 }
        }
        Text { visible: it.submenu; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: "›"; color: Theme.dimFg; font.pointSize: Theme.fontSize + 2 }
        MouseArea { id: im; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: it.triggered() }
    }

    // Big square quick action, like the top row of the iOS menu.
    component Quick: Rectangle {
        id: q
        property string label: ""
        property string icon: ""
        signal triggered()
        width: (menu.width - 12 - 6) / 2; height: 58; radius: Theme.material ? 12 : Theme.radius + 2
        color: qm.pressed ? Theme.pressed : qm.containsMouse ? Theme.hover : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.045)
        Column {
            anchors.centerIn: parent; spacing: 5
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: q.icon; size: 18; color: q.icon === "star" ? Theme.accentFg : Theme.fg }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: q.label; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
        }
        MouseArea { id: qm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: q.triggered() }
    }

    contentItem: Flickable {
        clip: true
        contentHeight: menu.showPlaylists ? lists.implicitHeight : main.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: main
            visible: !menu.showPlaylists
            spacing: 0
            Row {
                spacing: 6
                Quick {
                    icon: menu.track && menu.track.starred ? "star" : "unstar"
                    label: menu.track && menu.track.starred ? "Desfavoritar" : "Favoritar"
                    onTriggered: { menu.toggleStar(menu.track); menu.close() }
                }
                Quick { icon: "share"; label: "Compartilhar"; onTriggered: { menu.share(menu.track); menu.close() } }
            }
            Sep {}
            Item_ { icon: "next"; label: "Tocar a seguir"; onTriggered: { menu.playNext(menu.track); menu.close() } }
            Item_ { icon: "queue"; label: "Adicionar à fila"; onTriggered: { menu.enqueue(menu.track); menu.close() } }
            Item_ { icon: "playlist"; label: "Adicionar à playlist"; submenu: true; onTriggered: menu.showPlaylists = true }
            Item_ {
                readonly property bool isOn: !!menu.track && menu.track.id === menu.loopingId
                visible: !!menu.track && !menu.track.free
                icon: "repeat"
                label: isOn ? "Parar o trecho em loop" : "Repetir um trecho em loop"
                sub: isOn ? "" : "Escolha início e fim, para estudar"
                onTriggered: { menu.loopSection(menu.track); menu.close() }
            }
            Sep {}
            Item_ { icon: "station"; label: "Criar estação"; sub: "Músicas parecidas, sem parar"; onTriggered: { menu.startStation(menu.track); menu.close() } }
            Sep {}
            Item_ {
                icon: "albums"; label: "Ir para o álbum"; sub: menu.track && menu.track.album ? menu.track.album : ""
                visible: !!menu.track && menu.track.albumId !== null && menu.track.albumId !== undefined
                onTriggered: { menu.goToAlbum(menu.track); menu.close() }
            }
            Item_ {
                icon: "mic"; label: "Ir para o artista"; sub: menu.track ? (menu.track.artist || "") : ""
                visible: !!menu.track && !!menu.track.artist
                onTriggered: { menu.goToArtist(menu.track); menu.close() }
            }
            Sep {}
            Item_ {
                visible: Prefs.showExplicit && !!menu.track && !menu.track.free && menu.track.id > 0
                icon: "warning"
                label: menu.explicitShown ? "Tirar o selo E" : "Marcar como explícita"
                onTriggered: { menu.toggleExplicit(menu.track, menu.explicitShown); menu.close() }
            }
            Item_ { icon: "info"; label: "Informações e créditos"; onTriggered: { menu.showInfo(menu.track); menu.close() } }
            Item_ {
                visible: !!menu.track && !menu.track.free && menu.track.id > 0
                icon: "edit"; label: "Editar informações…"
                onTriggered: { menu.editInfo(menu.track); menu.close() }
            }
            Item_ { icon: "lyrics"; label: "Ver letra"; onTriggered: { menu.showLyrics(menu.track); menu.close() } }
            Item_ { icon: "copy"; label: "Copiar letra"; onTriggered: { menu.copyLyrics(menu.track); menu.close() } }
            Item_ { icon: "edit"; label: "Editar letra…"; onTriggered: { menu.editLyrics(menu.track); menu.close() } }
            Sep { visible: menu.isLocal }
            Item_ { icon: "folder-open"; label: "Mostrar na pasta"; visible: menu.isLocal; onTriggered: { menu.showInFolder(menu.track); menu.close() } }
        }
        Column {
            id: lists
            visible: menu.showPlaylists
            Item_ { label: "‹  Voltar"; onTriggered: menu.showPlaylists = false }
            Sep {}
            Repeater {
                model: menu.playlists
                Item_ {
                    required property var modelData
                    icon: "playlist"
                    label: modelData.name
                    onTriggered: { menu.addToPlaylist(menu.track, modelData.id); menu.close() }
                }
            }
            Item_ { icon: "add"; label: "Nova playlist…"; onTriggered: { menu.newPlaylistWith(menu.track); menu.close() } }
        }
    }
}
