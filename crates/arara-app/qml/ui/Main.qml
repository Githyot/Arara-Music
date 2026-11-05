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
    // CSD like GNOME apps; pass --ssd to fall back to server-side decorations.
    readonly property bool csd: Qt.application.arguments.indexOf("--ssd") < 0
    flags: csd ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window
    readonly property bool narrow: width < 620

    Binding { target: Theme; property: "dark"; value: library.dark }
    Binding { target: Theme; property: "accent"; value: library.accent }

    Library {
        id: library
        Component.onCompleted: { library.open(); player.restore() }
        onLibraryChanged: {
            albumGrid.albums = JSON.parse(library.albumsJson())
            artistGrid.artists = JSON.parse(library.artistsJson())
            nav.refresh()
        }
        onPlaylistsChanged: { sidebar.playlists = JSON.parse(library.playlistsJson()); if (nav.page === "playlist") nav.refresh() }
        onLyricsReady: (trackId, json) => {
            // qint64 arrives as an object in JS; compare as numbers
            if (player.current && player.current.id === Number(trackId)) { nowPlaying.lyrics = JSON.parse(json); nowPlaying.loadingLyrics = false }
        }
        onMediaCommand: (cmd, arg) => {
            var us = Number(arg)
            switch (cmd) {
            case "play": if (player.current) media.play(); break
            case "pause": media.pause(); break
            case "playpause": playerBar.toggle(); break
            case "stop": media.stop(); break
            case "next": player.next(); break
            case "previous": player.prev(); break
            case "seek": player.seekTo(media.position + us / 1000); break
            case "setposition": player.seekTo(us / 1000); break
            case "raise": win.show(); win.raise(); win.requestActivate(); break
            case "quit": win.close(); break
            }
        }
    }

    // ---------- playback & queue ----------
    QtObject {
        id: player
        property var queue: []
        property int index: -1
        property var current: index >= 0 && index < queue.length ? queue[index] : null
        property bool shuffle: false
        property var unshuffled: []
        property string repeat: "off"
        property bool restoring: false

        function playList(list, i) { queue = list.slice(); index = i; shuffle = false; start(true) }
        function start(autoplay) {
            if (!current) { media.stop(); return }
            media.source = current.url
            if (autoplay) { media.play(); library.recordPlay(current.id) }
            nowPlaying.lyrics = { kind: "none" }
            nowPlaying.loadingLyrics = true
            library.requestLyrics(current.id)
            save()
        }
        function next() {
            if (repeat === "one" && media.mediaStatus === MediaPlayer.EndOfMedia) { media.position = 0; media.play(); return }
            if (index + 1 < queue.length) { index++; start(true) }
            else if (repeat === "all" && queue.length > 0) { index = 0; start(true) }
        }
        function prev() { if (media.position > 3000 || index <= 0) media.position = 0; else { index--; start(true) } }
        function jump(i) { index = i; start(true) }
        function seekTo(ms) { media.position = Math.max(0, ms); library.mprisPosition(media.position, true) }

        function playNext(t) {
            if (!current) { playList([t], 0); return }
            var q = queue.slice(); q.splice(index + 1, 0, t); queue = q; save()
            toast.show("“" + t.title + "” vai tocar a seguir")
        }
        function enqueue(t) {
            if (!current) { playList([t], 0); return }
            var q = queue.slice(); q.push(t); queue = q; save()
            toast.show("Adicionada à fila")
        }
        function removeAt(i) {
            if (i === index) return
            var q = queue.slice(); q.splice(i, 1)
            if (i < index) index--
            queue = q; save()
        }
        function toggleShuffle() {
            if (!current) { shuffle = !shuffle; return }
            if (!shuffle) {
                unshuffled = queue.slice()
                var rest = queue.slice(index + 1)
                for (var k = rest.length - 1; k > 0; k--) { var j = Math.floor(Math.random() * (k + 1)); var x = rest[k]; rest[k] = rest[j]; rest[j] = x }
                queue = queue.slice(0, index + 1).concat(rest)
            } else {
                var id = current.id
                queue = unshuffled
                index = Math.max(0, queue.findIndex(function (t) { return t.id === id }))
            }
            shuffle = !shuffle; save()
        }
        function cycleRepeat() { repeat = repeat === "off" ? "all" : repeat === "all" ? "one" : "off"; library.saveQueue(snapshot()) }

        function snapshot() {
            return JSON.stringify({ ids: queue.map(function (t) { return t.id }), index: index, pos: Math.round(media.position), repeat: repeat })
        }
        function save() { if (!restoring) library.saveQueue(snapshot()) }
        function restore() {
            var q = JSON.parse(library.loadQueue())
            if (!q || !q.tracks || q.tracks.length === 0) return
            restoring = true
            queue = q.tracks; index = q.index; repeat = q.repeat || "off"
            start(false)
            pendingSeek = q.pos
            restoring = false
        }
        property real pendingSeek: -1
    }

    MediaPlayer {
        id: media
        audioOutput: AudioOutput { id: audio; volume: 1.0 }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) player.next()
            if (mediaStatus === MediaPlayer.LoadedMedia) applyPendingSeek()
        }
        // GStreamer only accepts a seek once the stream is seekable (or playing).
        function applyPendingSeek() {
            if (player.pendingSeek > 0 && seekable) { position = player.pendingSeek; player.pendingSeek = -1 }
        }
        onSeekableChanged: applyPendingSeek()
        onPlaybackStateChanged: { applyPendingSeek(); mpris.push() }
    }

    // MPRIS mirror: state on change, position once a second while playing.
    QtObject {
        id: mpris
        function push() {
            var st = media.playbackState === MediaPlayer.PlayingState ? "Playing" : media.playbackState === MediaPlayer.PausedState ? "Paused" : (player.current ? "Paused" : "Stopped")
            library.mprisUpdate(st, player.current ? JSON.stringify(player.current) : "null",
                                player.index + 1 < player.queue.length || player.repeat === "all", player.index > 0 || !!player.current, audio.volume)
        }
    }
    Connections { target: player; function onCurrentChanged() { mpris.push() } function onQueueChanged() { mpris.push() } }
    Timer {
        interval: 1000; repeat: true; running: media.playbackState === MediaPlayer.PlayingState
        property int ticks: 0
        onTriggered: { library.mprisPosition(media.position, false); if (++ticks % 10 === 0) player.save() }
    }

    // ---------- navigation ----------
    QtObject {
        id: nav
        property string page: "albums"
        property var album: null
        property var artist: null
        property var playlist: null
        property var history: []

        function go(p) {
            if (p !== page) history.push({ page: page, album: album, artist: artist, playlist: playlist })
            page = p; refresh()
            if (p === "songs") search.forceActiveFocus()
        }
        function back() {
            var h = history.pop()
            if (!h) { page = "albums"; return }
            page = h.page; album = h.album; artist = h.artist; playlist = h.playlist; refresh()
        }
        function root(p) { page = p; history = []; refresh(); if (p === "songs") search.forceActiveFocus() }
        function openAlbum(a) { album = a; albumPage.tracks = JSON.parse(library.albumTracksJson(a.id)); albumPage.contentY = 0; go("album") }
        function openAlbumById(id) {
            var a = albumGrid.albums.find(function (x) { return x.id === id })
            if (a) openAlbum(a)
        }
        function openArtist(a) { artist = a; artistAlbums.albums = JSON.parse(library.artistAlbumsJson(a.id)); go("artist") }
        function openArtistById(id) {
            var a = artistGrid.artists.find(function (x) { return x.id === id })
            if (a) openArtist(a)
        }
        function openPlaylist(p) { playlist = p; go("playlist") }
        function refresh() {
            if (page === "starred") listPage.tracks = JSON.parse(library.starredJson())
            else if (page === "recent") listPage.tracks = JSON.parse(library.recentJson())
            else if (page === "playlist" && playlist) {
                var lists = JSON.parse(library.playlistsJson())
                var p = lists.find(function (x) { return x.id === playlist.id })
                if (!p) { root("albums"); return }
                playlist = p
                listPage.tracks = JSON.parse(library.playlistTracksJson(p.id))
            }
        }
        readonly property string title: page === "album" && album ? album.title
            : page === "artist" && artist ? artist.name
            : page === "artists" ? "Artistas"
            : page === "starred" ? "Favoritas"
            : page === "recent" ? "Recentes"
            : page === "playlist" ? "Playlist"
            : page === "songs" ? "" : "Álbuns"
    }

    function onTrackMenu(t, x, y) { trackMenu.openAt(t, x, y, sidebar.playlists) }
    function onStar(t, s) { library.setStarred(t.id, s); t.starred = s; if (nav.page === "starred") nav.refresh() }

    // ---------- chrome ----------
    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: win.csd && win.visibility !== Window.Maximized && win.visibility !== Window.FullScreen ? 1 : 0
        radius: win.csd && win.visibility === Window.Windowed ? Theme.windowRadius : 0
        color: Theme.windowBg
        border.color: Theme.border; border.width: win.csd ? 1 : 0
        clip: true

        Sidebar {
            id: sidebar
            visible: !win.narrow
            width: visible ? 230 : 0
            anchors { left: parent.left; top: parent.top; bottom: playerBar.top }
            radius: frame.radius
            window: win
            page: nav.page
            playlistId: nav.playlist ? nav.playlist.id : -1
            footer: library.scanning ? library.status : library.trackCount + " faixas · " + library.albumCount + " álbuns"
            onNavigate: (p) => nav.root(p)
            onOpenPlaylist: (p) => { nav.history = []; nav.openPlaylist(p) }
            onNewPlaylist: prompt.ask("Nova playlist", "", "", "Criar", function (name) {
                var id = Number(library.createPlaylist(name))
                nav.openPlaylist({ id: id, name: name })
            })
        }

        Item {
            id: content
            anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: playerBar.top }

            HeaderBar {
                id: header
                anchors { left: parent.left; right: parent.right; top: parent.top }
                window: win
                showControls: win.csd
                title: nav.title
                leading: [
                    FlatButton { icon: "back"; visible: nav.history.length > 0 || nav.page === "album" || nav.page === "artist"; onClicked: nav.back() }
                ]
                trailing: [
                    Rectangle {
                        visible: nav.page === "songs"
                        width: Math.min(360, header.width - 200); height: 34; radius: Theme.radius
                        color: Theme.hover
                        border.color: search.activeFocus ? Theme.accent : "transparent"; border.width: 2
                        TextInput {
                            id: search
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: "white"
                            font.family: Theme.font; font.pointSize: Theme.fontSize
                            onTextChanged: searchTimer.restart()
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: !search.text; text: "Pesquisar na biblioteca"; color: Theme.dimFg; font: search.font }
                        }
                    },
                    FlatButton { icon: "search"; visible: nav.page !== "songs"; onClicked: nav.go("songs") }
                ]
            }
            Timer { id: searchTimer; interval: 120; onTriggered: songs.results = JSON.parse(library.searchJson(search.text)) }

            Item {
                id: stack
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom }

                AlbumGrid {
                    id: albumGrid
                    anchors.fill: parent
                    visible: nav.page === "albums"
                    onOpenAlbum: (a) => nav.openAlbum(a)
                }
                ArtistGrid {
                    id: artistGrid
                    anchors.fill: parent
                    visible: nav.page === "artists"
                    onOpenArtist: (a) => nav.openArtist(a)
                }
                Item {
                    anchors.fill: parent
                    visible: nav.page === "artist"
                    Text {
                        id: artistTitle
                        x: 24; y: 20
                        text: nav.artist ? nav.artist.name : ""
                        color: Theme.fg; font.family: Theme.font; font.pointSize: 20; font.weight: Font.Bold
                    }
                    AlbumGrid {
                        id: artistAlbums
                        anchors { left: parent.left; right: parent.right; top: artistTitle.bottom; bottom: parent.bottom }
                        onOpenAlbum: (a) => nav.openAlbum(a)
                    }
                }
                AlbumPage {
                    id: albumPage
                    anchors.fill: parent
                    visible: nav.page === "album"
                    album: nav.album
                    playingId: player.current ? player.current.id : -1
                    onPlay: (t, i) => player.playList(t, i)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onStarToggled: (t, s) => win.onStar(t, s)
                    onOpenArtist: (id) => nav.openArtistById(id)
                }
                SongsPage {
                    id: songs
                    anchors.fill: parent
                    visible: nav.page === "songs"
                    query: search.text
                    playingId: player.current ? player.current.id : -1
                    onPlay: (t, i) => player.playList(t, i)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onStarToggled: (t, s) => win.onStar(t, s)
                }
                TrackListPage {
                    id: listPage
                    anchors.fill: parent
                    visible: nav.page === "starred" || nav.page === "recent" || nav.page === "playlist"
                    title: nav.page === "starred" ? "Favoritas" : nav.page === "recent" ? "Tocadas recentemente" : (nav.playlist ? nav.playlist.name : "")
                    subtitle: tracks.length + (tracks.length === 1 ? " música" : " músicas")
                    emptyText: nav.page === "starred" ? "Nenhuma favorita" : nav.page === "recent" ? "Nada tocado ainda" : "Playlist vazia"
                    emptyHint: nav.page === "starred" ? "Clique na ☆ de uma música para favoritar." : nav.page === "playlist" ? "Use o menu ⋮ de uma música para adicionar aqui." : ""
                    removable: nav.page === "playlist"
                    editable: nav.page === "playlist"
                    playingId: player.current ? player.current.id : -1
                    onPlay: (t, i) => player.playList(t, i)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onStarToggled: (t, s) => win.onStar(t, s)
                    onRemoveAt: (i) => library.removeFromPlaylist(nav.playlist.id, i)
                    onRenameRequested: prompt.ask("Renomear playlist", "", nav.playlist.name, "Renomear", function (name) { library.renamePlaylist(nav.playlist.id, name) })
                    onDeleteRequested: prompt.confirm("Excluir “" + nav.playlist.name + "”?", "As músicas continuam na biblioteca.", "Excluir", function () {
                        var id = nav.playlist.id; nav.root("albums"); library.deletePlaylist(id)
                    })
                }

                // Empty state (AdwStatusPage)
                Column {
                    anchors.centerIn: parent
                    visible: nav.page === "albums" && albumGrid.count === 0
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
            position: player.pendingSeek > 0 ? player.pendingSeek : media.position
            duration: media.duration
            shuffle: player.shuffle
            repeat: player.repeat
            volume: audio.volume
            onToggle: playing ? media.pause() : (player.current ? media.play() : null)
            onNext: player.next()
            onPrev: player.prev()
            onSeek: (ms) => player.seekTo(ms)
            onExpand: nowPlaying.visible = true
            onToggleShuffle: player.toggleShuffle()
            onCycleRepeat: player.cycleRepeat()
            onVolumeMoved: (v) => { audio.volume = v; mpris.push() }
        }

        NowPlaying {
            id: nowPlaying
            visible: false
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: playerBar.top }
            track: player.current
            position: media.position
            queue: player.queue
            queueIndex: player.index
            onSeek: (ms) => player.seekTo(ms)
            onClose: visible = false
            onJump: (i) => player.jump(i)
            onRemoveAt: (i) => player.removeAt(i)
            MouseArea { anchors { left: parent.left; right: parent.right; top: parent.top } height: Theme.headerHeight; z: -1; onPressed: win.startSystemMove() }
        }

        // AdwToast
        Rectangle {
            id: toast
            property string text: ""
            function show(t) { text = t; opacity = 1; toastTimer.restart() }
            anchors { horizontalCenter: parent.horizontalCenter; bottom: playerBar.top; bottomMargin: 16 }
            width: toastText.implicitWidth + 40; height: 40; radius: 20
            color: Theme.dark ? "#e6e6e6" : "#2e2e32"
            opacity: 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Text { id: toastText; anchors.centerIn: parent; text: toast.text; color: Theme.dark ? "#1d1d20" : "#ffffff"; font.family: Theme.font; font.pointSize: Theme.fontSize }
            Timer { id: toastTimer; interval: 2600; onTriggered: toast.opacity = 0 }
        }
    }

    TrackMenu {
        id: trackMenu
        parent: frame
        onPlayNext: (t) => player.playNext(t)
        onEnqueue: (t) => player.enqueue(t)
        onAddToPlaylist: (t, pid) => {
            library.addToPlaylist(pid, JSON.stringify([t.id]))
            var p = sidebar.playlists.find(function (x) { return x.id === pid })
            toast.show("Adicionada a “" + (p ? p.name : "playlist") + "”")
        }
        onNewPlaylistWith: (t) => prompt.ask("Nova playlist", "Com “" + t.title + "”", "", "Criar", function (name) {
            var id = Number(library.createPlaylist(name))
            library.addToPlaylist(id, JSON.stringify([t.id]))
            toast.show("Playlist “" + name + "” criada")
        })
        onGoToAlbum: (t) => { nowPlaying.visible = false; nav.openAlbumById(t.albumId) }
    }
    TextPrompt { id: prompt }

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

    onClosing: player.save()

    Shortcut { sequence: "Space"; enabled: !search.activeFocus && !prompt.visible; onActivated: playerBar.toggle() }
    Shortcut { sequence: "Ctrl+F"; onActivated: nav.go("songs") }
    Shortcut { sequence: "Ctrl+Right"; onActivated: player.next() }
    Shortcut { sequence: "Ctrl+Left"; onActivated: player.prev() }
    Shortcut { sequence: "Ctrl+L"; onActivated: nowPlaying.visible = !nowPlaying.visible }
    Shortcut { sequence: "Escape"; onActivated: { if (nowPlaying.visible) nowPlaying.visible = false; else if (nav.history.length) nav.back() } }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.close() }
}
