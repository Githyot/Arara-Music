import QtQuick
import AraraStyle

// One remote server: status banner (last sync, errors, actions) + its albums.
Item {
    id: page
    property var server: null
    property bool syncing: false
    property alias albums: grid.albums
    signal openAlbum(var album)
    signal syncRequested()
    signal removeRequested()

    function ago(ts) {
        if (!ts) return "nunca sincronizado"
        var d = Math.max(0, Date.now() / 1000 - ts)
        if (d < 90) return "sincronizado agora"
        if (d < 3600) return "sincronizado há " + Math.round(d / 60) + " min"
        if (d < 86400) return "sincronizado há " + Math.round(d / 3600) + " h"
        return "sincronizado em " + new Date(ts * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }

    Rectangle {
        id: banner
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        height: 76; radius: Theme.cardRadius; color: Theme.cardBg
        Icon { id: ic; anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter } name: "server"; size: 32; color: Theme.dimFg }
        Column {
            anchors { left: ic.right; leftMargin: 14; right: actions.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                width: parent.width; elide: Text.ElideRight
                text: page.server ? page.server.name : ""
                color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize + 2; font.weight: Font.Bold
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: !page.server ? "" : (page.server.kind === "jellyfin" ? "Jellyfin" : "Subsonic") + " · " + page.server.user + " · " + page.server.url
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
            Row {
                spacing: 6
                Icon { visible: !!(page.server && page.server.error); name: "warning"; size: 14; color: Theme.destructive; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: !page.server ? "" : page.syncing ? "Sincronizando…"
                        : page.server.error ? page.server.error
                        : page.server.tracks.toLocaleString(Qt.locale(), "f", 0) + " faixas · " + page.ago(page.server.lastSync)
                    color: page.server && page.server.error && !page.syncing ? Theme.destructive : Theme.dimFg
                    font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                }
            }
        }
        Row {
            id: actions
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 6
            FlatButton {
                icon: "refresh"; circular: true; color: Theme.hover
                opacity: page.syncing ? 0.45 : 1
                onClicked: if (!page.syncing) page.syncRequested()
                RotationAnimation on rotation { running: page.syncing; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
            }
            FlatButton { icon: "trash"; circular: true; color: Theme.hover; onClicked: page.removeRequested() }
        }
    }

    AlbumGrid {
        id: grid
        anchors { left: parent.left; right: parent.right; top: banner.bottom; bottom: parent.bottom }
        onOpenAlbum: (a) => page.openAlbum(a)
    }
    Text {
        anchors.centerIn: grid
        visible: grid.count === 0
        text: page.syncing ? "Baixando o catálogo…" : "Nenhum álbum neste servidor"
        color: Theme.dimFg; font.family: Theme.font; font.pointSize: 14
    }
}
