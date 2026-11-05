import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtMultimedia
import AraraStyle
import io.github.arara

// Main window: AdwNavigationSplitView-style layout (sidebar + content),
// AdwBottomSheet-style player bar, full-screen "now playing" sheet.
Window {
    id: win
    width: 1100; height: 720
    minimumWidth: 360; minimumHeight: 480
    visible: true
    title: "Arara Music"
    color: "transparent"
    // CSD like GNOME apps; set ARARA_SSD=1 to fall back to server-side decorations.
    readonly property bool csd: Qt.application.arguments.indexOf("--ssd") < 0
    flags: csd ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window
    readonly property bool narrow: width < 620

    Library {
        id: library
        Component.onCompleted: { Theme.dark = library.dark; library.open() }
        onLibraryChanged: albumGrid.albums = JSON.parse(library.albumsJson())
        onLyricsReady: (trackId, json) => {
            // qint64 arrives as an object in JS; compare as numbers
            if (player.current && player.current.id === Number(trackId)) { nowPlaying.lyrics = JSON.parse(json); nowPlaying.loadingLyrics = false }
        }
    }

    // ---------- playback ----------
    QtObject {
        id: player
        property var queue: []
        property int index: -1
        property var current: index >= 0 && index < queue.length ? queue[index] : null
        function playList(list, i) { queue = list; index = i; start() }
        function start() {
            if (!current) return
            media.source = current.url
            media.play()
            nowPlaying.lyrics = { kind: "none" }
            nowPlaying.loadingLyrics = true
            library.requestLyrics(current.id)
        }
        function next() { if (index + 1 < queue.length) { index++; start() } }
        function prev() { if (media.position > 3000 || index === 0) media.position = 0; else { index--; start() } }
    }
    MediaPlayer {
        id: media
        audioOutput: AudioOutput { id: audio; volume: 1.0 }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) player.next()
    }

    // ---------- chrome ----------
    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: win.csd && win.visibility !== Window.Maximized && win.visibility !== Window.FullScreen ? 1 : 0
        radius: win.csd && win.visibility === Window.Windowed ? Theme.windowRadius : 0
        color: Theme.windowBg
        border.color: Theme.border; border.width: win.csd ? 1 : 0
        clip: true

        // Sidebar
        Rectangle {
            id: sidebar
            visible: !win.narrow
            width: visible ? 220 : 0
            anchors { left: parent.left; top: parent.top; bottom: playerBar.top }
            color: Theme.sidebarBg
            radius: frame.radius

            HeaderBar {
                id: sideHeader
                anchors { left: parent.left; right: parent.right; top: parent.top }
                window: win; showControls: false; background: "transparent"
                title: "Arara Music"
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: sideHeader.bottom; margins: 6 }
                spacing: 2
                SidebarRow { width: parent.width; icon: "menu"; text: "Álbuns"; current: stack.page === "albums"; onClicked: stack.page = "albums" }
                SidebarRow { width: parent.width; icon: "search"; text: "Músicas"; current: stack.page === "songs"; onClicked: { stack.page = "songs"; search.forceActiveFocus() } }
                SidebarRow { width: parent.width; icon: "lyrics"; text: "Tocando agora"; current: nowPlaying.visible; onClicked: nowPlaying.visible = true }
            }
            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                text: library.scanning ? library.status : library.trackCount + " faixas · " + library.albumCount + " álbuns"
                color: Theme.dimFg; wrapMode: Text.Wrap
                font.family: Theme.font; font.pointSize: Theme.fontSize - 2
            }
            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.border; opacity: 0.6 }
        }

        // Content
        Item {
            id: content
            anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: playerBar.top }

            HeaderBar {
                id: header
                anchors { left: parent.left; right: parent.right; top: parent.top }
                window: win
                showControls: win.csd
                title: stack.page === "album" && stack.album ? stack.album.title : stack.page === "songs" ? "" : "Álbuns"
                leading: [
                    FlatButton { icon: "back"; visible: stack.page === "album"; onClicked: stack.page = "albums" }
                ]
                trailing: [
                    Rectangle {
                        visible: stack.page === "songs"
                        width: Math.min(360, header.width - 200); height: 34; radius: Theme.radius
                        color: Theme.hover
                        TextInput {
                            id: search
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg; selectionColor: Theme.accent
                            font.family: Theme.font; font.pointSize: Theme.fontSize
                            onTextChanged: searchTimer.restart()
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: !search.text; text: "Pesquisar na biblioteca"; color: Theme.dimFg; font: search.font }
                        }
                    },
                    FlatButton { icon: "search"; visible: stack.page !== "songs"; onClicked: { stack.page = "songs"; search.forceActiveFocus() } }
                ]
            }
            Timer { id: searchTimer; interval: 120; onTriggered: songs.results = JSON.parse(library.searchJson(search.text)) }

            Item {
                id: stack
                property string page: "albums"
                property var album: null
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom }

                AlbumGrid {
                    id: albumGrid
                    anchors.fill: parent
                    visible: stack.page === "albums"
                    onOpenAlbum: (a) => { stack.album = a; albumPage.tracks = JSON.parse(library.albumTracksJson(a.id)); albumPage.contentY = 0; stack.page = "album" }
                }
                AlbumPage {
                    id: albumPage
                    anchors.fill: parent
                    visible: stack.page === "album"
                    album: stack.album
                    playingId: player.current ? player.current.id : -1
                    onPlay: (t, i) => player.playList(t, i)
                }
                SongsPage {
                    id: songs
                    anchors.fill: parent
                    visible: stack.page === "songs"
                    query: search.text
                    playingId: player.current ? player.current.id : -1
                    onPlay: (t, i) => player.playList(t, i)
                }

                // Empty state (AdwStatusPage)
                Column {
                    anchors.centerIn: parent
                    visible: stack.page === "albums" && albumGrid.count === 0
                    spacing: 10
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: Theme.glyph("lyrics"); color: Theme.dimFg; font.pointSize: 56 }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: library.scanning ? "Indexando sua biblioteca…" : "Nenhuma música encontrada"; color: Theme.fg; font.family: Theme.font; font.pointSize: 18; font.weight: Font.Bold }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: library.scanning ? library.status : library.libraryDir; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                }
            }
        }

        PlayerBar {
            id: playerBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            track: player.current
            playing: media.playbackState === MediaPlayer.PlayingState
            position: media.position
            duration: media.duration
            onToggle: playing ? media.pause() : (player.current ? media.play() : null)
            onNext: player.next()
            onPrev: player.prev()
            onSeek: (ms) => media.position = ms
            onExpand: nowPlaying.visible = true
        }

        NowPlaying {
            id: nowPlaying
            visible: false
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: playerBar.top }
            track: player.current
            position: media.position
            onSeek: (ms) => media.position = ms
            onClose: visible = false
            MouseArea { anchors { left: parent.left; right: parent.right; top: parent.top } height: Theme.headerHeight; z: -1; onPressed: win.startSystemMove() }
        }
    }

    // Edge resize handles for the frameless window.
    Repeater {
        model: win.csd ? [
            { e: Qt.LeftEdge, x: 0, y: 8, w: 6, h: -16, c: Qt.SizeHorCursor },
            { e: Qt.RightEdge, x: -6, y: 8, w: 6, h: -16, c: Qt.SizeHorCursor },
            { e: Qt.TopEdge, x: 8, y: 0, w: -16, h: 6, c: Qt.SizeVerCursor },
            { e: Qt.BottomEdge, x: 8, y: -6, w: -16, h: 6, c: Qt.SizeVerCursor },
            { e: Qt.BottomEdge | Qt.RightEdge, x: -10, y: -10, w: 10, h: 10, c: Qt.SizeFDiagCursor },
            { e: Qt.BottomEdge | Qt.LeftEdge, x: 0, y: -10, w: 10, h: 10, c: Qt.SizeBDiagCursor }
        ] : []
        MouseArea {
            required property var modelData
            x: modelData.x < 0 ? win.width + modelData.x : modelData.x
            y: modelData.y < 0 ? win.height + modelData.y : modelData.y
            width: modelData.w <= 0 ? win.width + modelData.w : modelData.w
            height: modelData.h <= 0 ? win.height + modelData.h : modelData.h
            cursorShape: modelData.c
            onPressed: win.startSystemResize(modelData.e)
        }
    }

    Shortcut { sequence: "Space"; onActivated: playerBar.toggle() }
    Shortcut { sequence: "Ctrl+F"; onActivated: { stack.page = "songs"; search.forceActiveFocus() } }
    Shortcut { sequence: "Escape"; onActivated: { if (nowPlaying.visible) nowPlaying.visible = false; else if (stack.page === "album") stack.page = "albums" } }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.close() }
}
