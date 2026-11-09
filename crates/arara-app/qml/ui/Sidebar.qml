import QtQuick
import AraraStyle
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC

// Navigation sidebar: library, categories, collections, playlists and
// servers, each in a section that folds away (state is remembered).
// The frame follows the look: GNOME split pane, floating macOS card,
// Material navigation drawer, Fluent pane over the Mica window.
Item {
    id: side
    property string page: "home"
    property int playlistId: -1
    property var playlists: []
    property var servers: []
    property int serverId: -1
    property bool syncing: false
    property string footer: ""
    property var window: null
    property real radius: 0
    property bool windowControls: false   // macOS puts the traffic lights here
    property bool allWindowButtons: false
    // Folded sections and rows the user hid in Preferences.
    property var collapsed: ({})
    property var hidden: []
    signal navigate(string page)
    signal openPlaylist(var playlist)
    signal newPlaylist()
    signal openServer(var server)
    signal addServer()
    signal setCollapsed(string key, bool value)

    function isOpen(k) { return !collapsed[k] }
    function shown(list) { return list.filter(function (r) { return side.hidden.indexOf(r.p) < 0 }) }

    readonly property real inset: Theme.apple ? 8 : 0

    Rectangle {
        id: card
        anchors { fill: parent; margins: side.inset; rightMargin: Theme.apple ? 0 : 0 }
        radius: Theme.apple ? 12 : side.radius
        color: Theme.sidebarBg
        border.width: Theme.apple ? 1 : 0
        border.color: Theme.border
        // square the inner edge so only the window corners are round
        Rectangle {
            visible: !Theme.apple && side.radius > 0
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: side.radius; color: parent.color
        }
    }

    HeaderBar {
        id: head
        anchors { left: card.left; right: card.right; top: card.top }
        window: side.window; showControls: false; background: "transparent"; divider: false
        title: Theme.apple ? "" : "Arara Music"
        leading: [
            WindowControls {
                visible: side.windowControls && Theme.apple
                Layout.leftMargin: 8
                window: side.window
            }
        ]
    }

    Flickable {
        QQC.ScrollBar.vertical: OverlayScrollBar {}
        id: flick
        anchors { left: card.left; right: card.right; top: head.bottom; bottom: foot.top; leftMargin: 6; rightMargin: 6; bottomMargin: 4 }
        contentHeight: col.height + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 0

            SidebarRow {
                width: col.width; icon: "home"; text: "Início"
                current: side.page === "home"
                onClicked: side.navigate("home")
            }
            SidebarRow {
                width: col.width; icon: "study"; text: "Estudos"
                current: side.page === "studies" || side.page === "practice"
                onClicked: side.navigate("studies")
            }
            Section {
                key: "library"; title: "Biblioteca"
                rows: [
                    { p: "albums", i: "albums", t: "Álbuns" },
                    { p: "artists", i: "artist", t: "Artistas" },
                    { p: "songs", i: "songs", t: "Músicas" }
                ]
            }
            Section {
                key: "categories"; title: "Categorias"
                rows: side.shown([
                    { p: "genre", i: "genre", t: "Gêneros" },
                    { p: "year", i: "year", t: "Anos" },
                    { p: "composer", i: "composer", t: "Compositores" },
                    { p: "folder", i: "folder", t: "Pastas" }
                ])
            }
            Section {
                key: "collections"; title: "Coleções"
                rows: side.shown([
                    { p: "starred", i: "star", t: "Favoritas" },
                    { p: "added", i: "added", t: "Recém-adicionadas" },
                    { p: "recent", i: "recent", t: "Tocadas recentemente" },
                    { p: "mostplayed", i: "plays", t: "Mais tocadas" },
                    { p: "recap", i: "recap", t: "Retrospectiva" }
                ])
            }
            Section {
                key: "playlists"; title: "Playlists"; addButton: true
                onAdd: side.newPlaylist()
                count: side.playlists.length
                rows: side.playlists.map(function (pl) { return { pl: pl, i: pl.smart ? "search" : "playlist", t: pl.name } })
                empty: "Crie uma playlist com o + ou pelo menu ⋮ de uma música."
            }
            Section {
                key: "servers"; title: "Servidores"; addButton: true
                visible: side.hidden.indexOf("servers") < 0
                onAdd: side.addServer()
                count: side.servers.length
                rows: side.servers.map(function (sv) { return { sv: sv, i: sv.error ? "warning" : "server", t: sv.name } })
                empty: "Ouça do seu Navidrome, Subsonic ou Jellyfin junto com as músicas locais."
            }
        }
    }

    // Library stats, kept apart from the list so they never cover a section.
    Item {
        id: foot
        anchors { left: card.left; right: card.right; bottom: card.bottom }
        height: footText.text ? footText.implicitHeight + 20 : 0
        Rectangle { visible: !Theme.material; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 } height: 1; color: Theme.border; opacity: 0.7 }
        Text {
            id: footText
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
            text: side.footer
            color: Theme.dimFg; wrapMode: Text.Wrap
            font.family: Theme.font; font.pointSize: Theme.fontSize - 2
        }
    }
    Rectangle {
        visible: Theme.gnome
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: 1; color: Theme.border; opacity: 0.6
    }

    component Section: Column {
        id: sec
        property string key: ""
        property string title: ""
        property var rows: []
        property bool addButton: false
        property int count: -1
        property string empty: ""
        signal add()
        readonly property bool open: side.isOpen(key)
        width: col.width
        visible: rows.length > 0 || empty !== ""

        SectionHeader {
            width: parent.width
            text: sec.title
            collapsed: !sec.open
            addButton: sec.addButton
            count: sec.count
            onToggled: side.setCollapsed(sec.key, sec.open)
            onAdd: sec.add()
        }
        Item {
            width: parent.width
            height: sec.open ? inner.height : 0
            clip: true
            Behavior on height { NumberAnimation { duration: Theme.ms(200); easing.type: Easing.OutCubic } }
            Column {
                id: inner
                width: parent.width
                spacing: Theme.material ? 0 : 2
                opacity: sec.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.ms(160) } }
                Repeater {
                    model: sec.rows
                    SidebarRow {
                        required property var modelData
                        width: inner.width; icon: modelData.i; text: modelData.t
                        current: modelData.pl ? (side.page === "playlist" && side.playlistId === modelData.pl.id)
                            : modelData.sv ? (side.page === "server" && side.serverId === modelData.sv.id)
                            : side.page === modelData.p || (modelData.p === "albums" && side.page === "album") || (modelData.p === "artists" && side.page === "artist")
                        onClicked: modelData.pl ? side.openPlaylist(modelData.pl) : modelData.sv ? side.openServer(modelData.sv) : side.navigate(modelData.p)
                    }
                }
                Text {
                    visible: sec.rows.length === 0 && sec.empty !== ""
                    x: 12; width: inner.width - 24; wrapMode: Text.Wrap
                    topPadding: 2; bottomPadding: 6
                    text: sec.empty
                    color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2
                }
            }
        }
    }
}
