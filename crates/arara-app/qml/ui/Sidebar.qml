import QtQuick
import AraraStyle

// AdwNavigationSplitView sidebar: library sections, then the user's playlists.
Rectangle {
    id: side
    property string page: "albums"
    property int playlistId: -1
    property var playlists: []
    property string footer: ""
    property var window: null
    signal navigate(string page)
    signal openPlaylist(var playlist)
    signal newPlaylist()

    color: Theme.sidebarBg

    HeaderBar {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        window: side.window; showControls: false; background: "transparent"
        title: "Arara Music"
    }

    Flickable {
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; margins: 6 }
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 2
            Repeater {
                model: [
                    { p: "albums", i: "menu", t: "Álbuns" },
                    { p: "artists", i: "artist", t: "Artistas" },
                    { p: "songs", i: "search", t: "Músicas" },
                    { p: "starred", i: "star", t: "Favoritas" },
                    { p: "recent", i: "recent", t: "Recentes" }
                ]
                SidebarRow {
                    required property var modelData
                    width: col.width; icon: modelData.i; text: modelData.t
                    current: side.page === modelData.p || (modelData.p === "albums" && side.page === "album") || (modelData.p === "artists" && side.page === "artist")
                    onClicked: side.navigate(modelData.p)
                }
            }
            Item {
                width: col.width; height: 40
                Text {
                    anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 6 }
                    text: "Playlists"; color: Theme.dimFg
                    font.family: Theme.font; font.pointSize: Theme.fontSize - 1; font.weight: Font.Bold
                }
                FlatButton { anchors { right: parent.right; bottom: parent.bottom } size: 28; icon: "add"; onClicked: side.newPlaylist() }
            }
            Repeater {
                model: side.playlists
                SidebarRow {
                    required property var modelData
                    width: col.width; icon: "playlist"; text: modelData.name
                    current: side.page === "playlist" && side.playlistId === modelData.id
                    onClicked: side.openPlaylist(modelData)
                }
            }
            Text {
                visible: side.playlists.length === 0
                x: 12; width: col.width - 24; wrapMode: Text.Wrap
                text: "Crie uma playlist com o + ou pelo menu ⋮ de uma música."
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2
            }
        }
    }

    Text {
        id: foot
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
        text: side.footer
        color: Theme.dimFg; wrapMode: Text.Wrap
        font.family: Theme.font; font.pointSize: Theme.fontSize - 2
    }
    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.border; opacity: 0.6 }
}
