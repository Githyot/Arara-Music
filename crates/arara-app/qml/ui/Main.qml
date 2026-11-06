import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtMultimedia
import QtQuick.Dialogs
import AraraStyle
import io.github.arara

// Main window: AdwNavigationSplitView-style layout (sidebar + content),
// AdwBottomSheet-style player bar, full-screen "now playing" sheet.
Window {
    id: win
    width: 1100; height: 720
    minimumWidth: 720; minimumHeight: 520
    visible: true
    title: "Arara Music"
    color: "transparent"
    // CSD like GNOME apps; pass --ssd to fall back to server-side decorations.
    readonly property bool csd: Qt.application.arguments.indexOf("--ssd") < 0
    flags: csd ? (Qt.Window | Qt.FramelessWindowHint) : Qt.Window
    // Below this width the sidebar slides over the content; the player panel always stays.
    readonly property bool narrow: width < 900
    // Wide windows dock the player on the right (like Nocturne); narrow ones keep the bottom bar.
    readonly property bool wide: width >= 1000
    property bool panelOpen: true
    readonly property bool panelDocked: !lyricsMode
    property bool lyricsMode: false
    // ---------- preferences ----------
    // Every setting lives here, typed; stored as "pref:<key>" strings
    // (booleans as "1"/"0", lists and maps as JSON).
    readonly property var prefDefaults: ({
        theme: "gnome", scheme: "system", accent: "theme", panelcolors: true,
        tilesize: "medium", fontscale: 1.0, compact: false, reducemotion: false,
        replaygain: true, rgmode: "track", preamp: 0, autoplay: false, restore: true, remaining: true,
        autolyrics: true, lyricspanel: true, duets: true, lyricsscale: 1, lyricsoffset: 0,
        hidden: [], collapsed: ({ categories: true }), dlworkers: 2, jamendo: "", winbuttons: "close"
    })
    property var prefs: prefDefaults
    function loadPrefs() {
        var p = {}
        for (var k in prefDefaults) {
            var d = prefDefaults[k], raw = library.setting(k, "\u0001")
            if (raw === "\u0001") { p[k] = d; continue }
            if (typeof d === "boolean") p[k] = raw === "1"
            else if (typeof d === "number") p[k] = isNaN(Number(raw)) ? d : Number(raw)
            else if (typeof d === "object") { try { p[k] = JSON.parse(raw) } catch (e) { p[k] = d } }
            else p[k] = raw
        }
        // 0.6 stored the cover accent as its own switch
        if (library.setting("accent", "") === "" && library.setting("coveraccent", "0") === "1") p.accent = "cover"
        prefs = p
    }
    function setPref(k, v) {
        var p = Object.assign({}, prefs); p[k] = v; prefs = p
        var d = prefDefaults[k]
        library.setSetting(k, typeof d === "boolean" ? (v ? "1" : "0") : typeof d === "object" ? JSON.stringify(v) : String(v))
    }
    function resetPrefs() {
        for (var k in prefDefaults) if (k !== "jamendo" && k !== "hidden" && k !== "collapsed") setPref(k, prefDefaults[k])
        toast.show("Preferências restauradas")
    }
    readonly property bool autoplay: prefs.autoplay
    readonly property bool coverAccent: prefs.accent === "cover"
    readonly property bool autoLyrics: prefs.autolyrics
    readonly property string jamendoKey: prefs.jamendo
    property var lyrics: ({ kind: "none" })
    property bool loadingLyrics: false
    // Blurred cover + sampled colours of the current track, for backgrounds.
    property string backdrop: ""
    property var coverColors: []
    function refreshCoverLook() {
        var c = player.current ? player.current.cover : ""
        backdrop = c ? library.coverBlur(c) : ""
        coverColors = c ? JSON.parse(library.coverColors(c)) : []
    }
    // Accent from the cover (Euphonica-style): the most saturated sampled colour.
    readonly property color coverAccentColor: {
        var best = null, bs = -1
        for (var i = 0; i < coverColors.length; i++) {
            var c = Qt.color(coverColors[i]); if (c.hslSaturation > bs) { bs = c.hslSaturation; best = c }
        }
        return best ? Qt.hsla(best.hslHue, Math.max(0.55, best.hslSaturation), 0.5, 1) : library.accent
    }
    property bool drawerOpen: false
    onNarrowChanged: drawerOpen = false
    // Volume chosen by the user; ReplayGain scales the real output under it.
    property real userVolume: 1.0
    readonly property bool replayGain: prefs.replaygain
    readonly property real gainFactor: {
        var t = player.current
        if (!replayGain || !t) return 1.0
        var has = function (x) { return x !== undefined && x !== null }
        var g = prefs.rgmode === "album" ? (has(t.albumGain) ? t.albumGain : t.gain) : (has(t.gain) ? t.gain : t.albumGain)
        if (has(g)) g = Number(g) + Number(prefs.preamp)
        if (g === undefined || g === null) return 1.0
        return Math.min(1.0, Math.pow(10, Number(g) / 20))
    }

    Binding { target: Theme; property: "style"; value: win.prefs.theme }
    Binding { target: Theme; property: "dark"; value: win.prefs.scheme === "system" ? library.dark : win.prefs.scheme === "dark" }
    Binding {
        target: Theme; property: "accent"
        value: {
            var a = win.prefs.accent
            if (a === "cover") return win.coverColors.length ? win.coverAccentColor : (Theme.gnome ? library.accent : Theme.styleAccent)
            if (a === "system") return library.accent
            if (a === "theme") return Theme.gnome ? library.accent : Theme.styleAccent
            return a
        }
    }
    Binding {
        target: Theme; property: "accentInk"
        value: { var c = Qt.color(Theme.accent); return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b > 0.6 ? "#1c1b1f" : "#ffffff" }
    }
    Binding { target: Theme; property: "tileMin"; value: ({ small: 120, medium: 150, large: 200 })[win.prefs.tilesize] || 150 }
    Binding { target: Theme; property: "fontScale"; value: win.prefs.fontscale }
    Binding { target: Theme; property: "compact"; value: win.prefs.compact }
    Binding { target: Theme; property: "reduceMotion"; value: win.prefs.reducemotion }
    Binding { target: Prefs; property: "lyricsOffset"; value: win.prefs.lyricsoffset }
    Binding { target: Prefs; property: "lyricsScale"; value: win.prefs.lyricsscale }
    Binding { target: Prefs; property: "lyricsDuets"; value: win.prefs.duets }
    Binding { target: Prefs; property: "lyricsInPanel"; value: win.prefs.lyricspanel }
    Binding { target: Prefs; property: "remainingTime"; value: win.prefs.remaining }

    Library {
        id: library
        Component.onCompleted: {
            library.open()
            win.userVolume = Number(library.setting("volume", "1"))
            win.loadPrefs()
            win.panelOpen = library.setting("panel", "1") === "1"
            if (win.prefs.restore) player.restore()
        }
        onLibraryChanged: {
            albumGrid.albums = JSON.parse(library.albumsJson())
            artistGrid.artists = JSON.parse(library.artistsJson())
            if (songs.loaded) songs.reload()
            nav.refresh()
        }
        onServersChanged: {
            sidebar.servers = JSON.parse(library.serversJson())
            if (nav.page === "server") nav.refresh()
        }
        onImportFinished: (json) => importDialog.finished(json)
        onPathPicked: (purpose, path) => {
            if (purpose === "library") library.changeLibraryDir(path)
            else if (purpose === "addlibrary") { library.addLibraryDir(path); foldersDialog.dirs = JSON.parse(library.libraryDirsJson()) }
            else importDialog.pickedPath(path)
        }
        onPickerUnavailable: (purpose, directory) => {
            if (purpose === "library" || purpose === "addlibrary") { folderDialog.adding = purpose === "addlibrary"; folderDialog.open() }
            else importDialog.fallback(directory)
        }
        onServerAdded: (ok, message) => { addServer.finished(ok, message); if (ok) toast.show(message) }
        onPlaylistsChanged: { sidebar.playlists = JSON.parse(library.playlistsJson()); if (nav.page === "playlist") nav.refresh() }
        onFreeResults: (q, json, errs) => freePage.setResults(q, json, errs)
        onDownloadEvent: (id, kind, pct, msg) => {
            freePage.onEvent(id, kind, pct, msg)
            if (kind === "done") toast.show(msg.endsWith("|lrc") ? "Baixada, com a letra sincronizada" : "Música baixada para a biblioteca")
            else if (kind === "here") toast.show("Essa música já está na sua biblioteca")
            else if (kind === "failed") toast.show("Não foi possível baixar: " + msg)
        }
        onLyricsReady: (trackId, json) => {
            // qint64 arrives as an object in JS; compare as numbers
            if (player.current && player.current.id === Number(trackId)) { win.lyrics = JSON.parse(json); win.loadingLyrics = false }
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
            win.lyrics = { kind: "none" }
            win.loadingLyrics = true
            library.requestLyrics(current.id)
            save()
        }
        function next() {
            if (repeat === "one" && media.mediaStatus === MediaPlayer.EndOfMedia) { media.position = 0; media.play(); return }
            if (index + 1 < queue.length) { index++; start(true) }
            else if (repeat === "all" && queue.length > 0) { index = 0; start(true) }
            else if (win.autoplay && current && extendAutoplay()) { index++; start(true) }
        }
        function prev() { if (media.position > 3000 || index <= 0) media.position = 0; else { index--; start(true) } }
        function jump(i) { index = i; start(true) }
        // Autoplay: when the queue runs out, append tracks like the last ones.
        function extendAutoplay() {
            var recent = queue.slice(-200).map(function (t) { return t.id })
            var more = JSON.parse(library.autoplayJson(current.id, JSON.stringify(recent), 25))
            if (more.length === 0) return false
            queue = queue.concat(more); save()
            toast.show("Reprodução automática: " + more.length + " músicas na fila")
            return true
        }
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
        function move(from, to) {
            var cur = current
            var q = queue.slice(); var t = q.splice(from, 1)[0]; q.splice(to, 0, t)
            queue = q; index = q.indexOf(cur); save()
        }
        // Remove tracks that no longer exist (e.g. a removed server) from the queue.
        function dropWhere(pred) {
            var cur = current, q = queue.filter(function (t) { return !pred(t) })
            if (q.length === queue.length) return
            if (cur && pred(cur)) { media.stop(); queue = q; index = q.length ? 0 : -1; if (current) start(false) }
            else { queue = q; index = q.indexOf(cur) }
            save()
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
        // Qt picks the default output only once, at startup. Follow the output chosen in
        // GNOME (headset, HDMI, line out…) whenever it changes, even mid-song.
        audioOutput: AudioOutput { id: audio; volume: win.userVolume * win.gainFactor; device: sysAudio.defaultAudioOutput }
        // A missing file or unreachable server: say so and move on, but don't
        // spin through a whole queue of broken tracks.
        property int failures: 0
        onErrorOccurred: (error, message) => {
            if (!player.current) return
            toast.show("Não foi possível tocar “" + player.current.title + "”")
            if (++failures < 3) player.next()
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) player.next()
            if (mediaStatus === MediaPlayer.LoadedMedia) applyPendingSeek()
        }
        // GStreamer only accepts a seek once the stream is seekable (or playing).
        function applyPendingSeek() {
            if (player.pendingSeek > 0 && seekable) { position = player.pendingSeek; player.pendingSeek = -1 }
        }
        onSeekableChanged: applyPendingSeek()
        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.PlayingState) failures = 0
            applyPendingSeek(); mpris.push()
            library.setPlaying(playbackState === MediaPlayer.PlayingState)
        }
    }

    // Current lyric line → D-Bus (for desktop widgets / floating lyrics).
    readonly property int lyricIndex: {
        var ls = win.lyrics && win.lyrics.kind === "synced" ? win.lyrics.lines : []
        var lo = 0, hi = ls.length - 1, ans = -1, pos = media.position
        while (lo <= hi) { var mid = (lo + hi) >> 1; if (ls[mid].t <= pos) { ans = mid; lo = mid + 1 } else hi = mid - 1 }
        return ans
    }
    onLyricIndexChanged: {
        var ls = win.lyrics && win.lyrics.kind === "synced" ? win.lyrics.lines : []
        var t = player.current
        library.publishLyricLine(lyricIndex >= 0 ? (ls[lyricIndex].text || "") : "", lyricIndex + 1 < ls.length ? (ls[lyricIndex + 1].text || "") : "",
                                 t ? t.title : "", t ? t.artist || "" : "")
    }

    // MPRIS mirror: state on change, position once a second while playing.
    QtObject {
        id: mpris
        function push() {
            var st = media.playbackState === MediaPlayer.PlayingState ? "Playing" : media.playbackState === MediaPlayer.PausedState ? "Paused" : (player.current ? "Paused" : "Stopped")
            library.mprisUpdate(st, player.current ? JSON.stringify(player.current) : "null",
                                player.index + 1 < player.queue.length || player.repeat === "all", player.index > 0 || !!player.current, win.userVolume)
        }
    }
    MediaDevices {
        id: sysAudio
        onAudioOutputsChanged: audio.device = sysAudio.defaultAudioOutput
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
        property var server: null
        property var history: []
        // Sidebar entry the current view belongs to (an album opened from a server keeps "server").
        property string section: "albums"

        function go(p) {
            // Reassign (not push) so bindings on history.length, like the back button, update.
            if (p !== page) history = history.concat([{ page: page, section: section, album: album, artist: artist, playlist: playlist, server: server }])
            page = p; if (p === "songs") section = "songs"
            refresh()
            if (p === "songs") search.forceActiveFocus()
        }
        function back() {
            var h = history.length > 0 ? history[history.length - 1] : null
            history = history.slice(0, -1)
            if (!h) { root("albums"); return }
            page = h.page; section = h.section || h.page; album = h.album; artist = h.artist; playlist = h.playlist; server = h.server; refresh()
        }
        function root(p) {
            win.lyricsMode = false; page = p; section = p; history = []; win.drawerOpen = false
            if (p === "added") { catSongs.open("", "Adicionadas recentemente", "added") }
            refresh()
            if (p === "songs") search.forceActiveFocus()
        }
        // Category entry (a genre, a year, a composer or a folder) → its songs.
        function openGroup(kind, g) {
            var q = kind === "year" ? "ano:" + g.key : kind === "folder" ? "pasta:\"" + g.key + "\"" : (kind === "genre" ? "genero:" : "compositor:") + "\"" + g.key + "\""
            var label = kind === "genre" ? "Gênero" : kind === "year" ? "Ano" : kind === "composer" ? "Compositor" : "Pasta"
            catSongs.open(q, label + ": " + g.name, kind === "folder" ? "album" : "artist")
            go("group")
        }
        function rootPlaylist(p) { win.lyricsMode = false; playlist = p; page = "playlist"; section = "playlist"; history = []; win.drawerOpen = false; refresh() }
        function rootServer(sv) { win.lyricsMode = false; server = sv; page = "server"; section = "server"; history = []; win.drawerOpen = false; refresh() }
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
        function openServer(s) { server = s; go("server") }
        function refresh() {
            if (page === "server" && server) {
                var all = JSON.parse(library.serversJson())
                var sv = all.find(function (x) { return x.id === server.id })
                if (!sv) { root("albums"); return }
                server = sv
                serverPage.albums = JSON.parse(library.serverAlbumsJson(sv.id))
            }
            if (page === "genre" || page === "year" || page === "composer" || page === "folder") { groupsPage.kind = page; groupsPage.groups = JSON.parse(library.groupsJson(page)) }
            if (page === "starred") listPage.tracks = JSON.parse(library.starredJson())
            else if (page === "mostplayed") listPage.tracks = JSON.parse(library.mostPlayedJson())
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
            : page === "recent" ? "Tocadas recentemente"
            : page === "mostplayed" ? "Mais tocadas"
            : page === "added" ? "Adicionadas recentemente"
            : page === "genre" ? "Gêneros" : page === "year" ? "Anos" : page === "composer" ? "Compositores" : page === "folder" ? "Pastas"
            : page === "group" ? ""
            : page === "playlist" ? "Playlist"
            : page === "server" ? "Servidor"
            : page === "songs" ? "Músicas" : page === "free" ? "" : "Álbuns"
    }

    function setVolume(v) { win.userVolume = v; volumeSave.restart(); mpris.push() }
    function saveSmart(q, sort, suggested) {
        prompt.ask("Salvar como playlist inteligente", "Ela se atualiza sozinha com as músicas que combinam com “" + q + "”.", suggested, "Salvar", function (name) {
            var id = Number(library.saveSmartPlaylist(-1, name, q, sort, 0))
            nav.rootPlaylist({ id: id, name: name, smart: true })
            toast.show("Playlist inteligente “" + name + "” criada")
        })
    }
    Connections { target: player; function onCurrentChanged() { win.refreshCoverLook() } }
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

        // Scrim behind the sidebar when it slides over the content (narrow windows).
        Rectangle {
            anchors.fill: parent; z: 9
            visible: win.narrow && win.drawerOpen
            color: "#4d000000"
            MouseArea { anchors.fill: parent; onClicked: win.drawerOpen = false }
        }
        Sidebar {
            id: sidebar
            z: 10
            visible: !win.narrow || win.drawerOpen
            width: Theme.sidebarWidth
            anchors { left: parent.left; top: parent.top; bottom: playerBar.visible ? playerBar.top : parent.bottom }
            radius: frame.radius
            window: win
            windowControls: win.csd
            collapsed: win.prefs.collapsed
            hidden: win.prefs.hidden
            onSetCollapsed: (key, value) => { var c = Object.assign({}, win.prefs.collapsed); c[key] = value; win.setPref("collapsed", c) }
            page: nav.section
            playlistId: nav.playlist ? nav.playlist.id : -1
            footer: library.scanning ? library.status : library.trackCount + " faixas · " + library.albumCount + " álbuns" + (library.lyricsProgress ? "\n" + library.lyricsProgress : "")
            onNavigate: (p) => nav.root(p)
            onOpenPlaylist: (p) => nav.rootPlaylist(p)
            servers: []
            serverId: nav.server ? nav.server.id : -1
            onOpenServer: (sv) => nav.rootServer(sv)
            onAddServer: addServer.start()
            onNewPlaylist: prompt.ask("Nova playlist", "", "", "Criar", function (name) {
                var id = Number(library.createPlaylist(name))
                nav.rootPlaylist({ id: id, name: name })
            })
        }

        Item {
            id: content
            anchors { left: win.narrow ? parent.left : sidebar.right; right: win.panelDocked ? playerPanel.left : parent.right; top: parent.top; bottom: playerBar.visible ? playerBar.top : parent.bottom }

            // Fluent: the content sits on a lighter layer with a rounded corner over the Mica window.
            Rectangle {
                visible: Theme.fluent
                anchors { fill: parent; topMargin: 0 }
                color: Theme.viewBg
                radius: 8
                Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.width / 2; color: parent.color }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: parent.height / 2; color: parent.color }
                Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 8 } width: 1; color: Theme.border }
            }
            HeaderBar {
                id: header
                anchors { left: parent.left; right: parent.right; top: parent.top }
                window: win
                background: Theme.fluent ? "transparent" : Theme.headerBg
                showControls: win.csd && !win.panelDocked
                allWindowButtons: win.prefs.winbuttons === "all"
                title: nav.title
                leading: [
                    WindowControls { visible: win.csd && Theme.apple && win.narrow; window: win; Layout.leftMargin: 8; Layout.rightMargin: 4 },
                    FlatButton { icon: "sidebar"; visible: win.narrow; checked: win.drawerOpen; onClicked: win.drawerOpen = !win.drawerOpen },
                    FlatButton { icon: "back"; visible: nav.history.length > 0; onClicked: nav.back() }
                ]
                trailing: [
                    Rectangle {
                        visible: true
                        width: Math.max(160, Math.min(340, header.width * 0.36)); height: Theme.material ? 40 : 34
                        radius: Theme.material ? height / 2 : Theme.radius
                        Layout.preferredWidth: width
                        clip: true
                        color: Theme.fieldBg
                        border.color: search.activeFocus ? Theme.accent : Theme.fluent ? Theme.border : "transparent"
                        border.width: search.activeFocus ? 2 : 1
                        // Fluent: accent underline instead of a full focus ring
                        Rectangle { visible: Theme.fluent && search.activeFocus; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 2; color: Theme.accent }
                        Icon { id: searchIcon; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } name: "search"; size: 14; color: Theme.dimFg }
                        TextInput {
                            id: search
                            anchors { fill: parent; leftMargin: 32; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.accentInk
                            font.family: Theme.font; font.pointSize: Theme.fontSize
                            onTextChanged: {
                                if (activeFocus && text !== "" && nav.page !== "songs") nav.root("songs")
                                win.lyricsMode = false
                                searchTimer.restart()
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: !search.text; text: "Pesquisar na biblioteca"; color: Theme.dimFg; font: search.font }
                        }
                    },
                    FlatButton { id: menuButton; icon: "menu"; onClicked: appMenu.openUnder(menuButton) }
                ]
            }
            Timer { id: searchTimer; interval: 120; onTriggered: songs.search(search.text) }

            Item {
                id: stack
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom }
                // Each page change fades the new page in and lifts it a little.
                transform: Translate { id: stackLift }
                Connections {
                    target: nav
                    function onPageChanged() { pageIn.restart() }
                }
                ParallelAnimation {
                    id: pageIn
                    NumberAnimation { target: stack; property: "opacity"; from: Theme.reduceMotion ? 1 : 0.35; to: 1; duration: Theme.ms(220); easing.type: Easing.OutCubic }
                    NumberAnimation { target: stackLift; property: "y"; from: Theme.reduceMotion ? 0 : 10; to: 0; duration: Theme.ms(260); easing.type: Easing.OutCubic }
                }

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
                        color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize; font.weight: Theme.titleWeight
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
                ServerPage {
                    id: serverPage
                    anchors.fill: parent
                    visible: nav.page === "server"
                    server: nav.server
                    syncing: library.syncing
                    onOpenAlbum: (a) => nav.openAlbum(a)
                    onSyncRequested: library.syncServers(nav.server.id)
                    onRemoveRequested: prompt.confirm("Remover “" + nav.server.name + "”?",
                        "As músicas desse servidor saem da biblioteca e das playlists. Nada é apagado no servidor.", "Remover", function () {
                        var id = nav.server.id, base = nav.server.url; nav.root("albums"); library.removeServer(id); player.dropWhere(function (t) { return t.remote && t.url.indexOf(base) === 0 })
                    })
                }
                GroupsPage {
                    id: groupsPage
                    anchors.fill: parent
                    visible: nav.page === "genre" || nav.page === "year" || nav.page === "composer" || nav.page === "folder"
                    onOpen: (g) => nav.openGroup(kind, g)
                }
                SongsPage {
                    id: catSongs
                    anchors.fill: parent
                    visible: nav.page === "group" || nav.page === "added"
                    playingId: player.current ? player.current.id : -1
                    onPlay: (t, i) => player.playList(t, i)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onStarToggled: (t, s) => win.onStar(t, s)
                    onSaveSmart: (q, sort) => win.saveSmart(q, sort, heading)
                }
                SongsPage {
                    id: songs
                    onSaveSmart: (q, sort) => win.saveSmart(q, sort, "")
                    anchors.fill: parent
                    visible: nav.page === "songs"
                    playingId: player.current ? player.current.id : -1
                    onPlay: (t, i) => player.playList(t, i)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onStarToggled: (t, s) => win.onStar(t, s)
                }
                TrackListPage {
                    id: listPage
                    anchors.fill: parent
                    visible: nav.page === "starred" || nav.page === "recent" || nav.page === "playlist" || nav.page === "mostplayed"
                    title: nav.page === "starred" ? "Favoritas" : nav.page === "recent" ? "Tocadas recentemente" : nav.page === "mostplayed" ? "Mais tocadas" : (nav.playlist ? nav.playlist.name : "")
                    subtitle: tracks.length + (tracks.length === 1 ? " música" : " músicas")
                    emptyText: nav.page === "starred" ? "Nenhuma favorita" : nav.page === "recent" || nav.page === "mostplayed" ? "Nada tocado ainda" : nav.playlist && nav.playlist.smart ? "Nenhuma música combina com esta busca" : "Playlist vazia"
                    emptyHint: nav.page === "starred" ? "Clique na ☆ de uma música para favoritar." : nav.page === "playlist" ? "Use o menu ⋮ de uma música para adicionar aqui." : ""
                    removable: nav.page === "playlist" && !(nav.playlist && nav.playlist.smart)
                    editable: nav.page === "playlist"
                    playingId: player.current ? player.current.id : -1
                    onPlay: (t, i) => player.playList(t, i)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onStarToggled: (t, s) => win.onStar(t, s)
                    onRemoveAt: (i) => library.removeFromPlaylist(nav.playlist.id, i)
                    onMoveItem: (f, t) => library.moveInPlaylist(nav.playlist.id, f, t)
                    onRenameRequested: prompt.ask("Renomear playlist", "", nav.playlist.name, "Renomear", function (name) { library.renamePlaylist(nav.playlist.id, name) })
                    onDeleteRequested: prompt.confirm("Excluir “" + nav.playlist.name + "”?", "As músicas continuam na biblioteca.", "Excluir", function () {
                        var id = nav.playlist.id; nav.root("albums"); library.deletePlaylist(id)
                    })
                }

                FreePage {
                    id: freePage
                    anchors.fill: parent
                    visible: nav.page === "free"
                    jamendoKey: win.jamendoKey
                    playingIndex: {
                        var c = player.current
                        if (!c || !c.free) return -1
                        for (var i = 0; i < results.length; i++) if (results[i].stream_url === c.url) return i
                        return -1
                    }
                    onPlay: (tracks, i) => player.playList(tracks, i)
                    onDownload: (t) => { if (!library.downloadFree(JSON.stringify(t))) toast.show("Este artista não permite baixar esta música") }
                    onCancel: (id) => library.cancelDownload(id)
                    onSaveKey: (k) => { win.setPref("jamendo", k); toast.show("Chave do Jamendo salva"); if (lastQuery) search(lastQuery) }
                }

                LyricsScreen {
                    id: lyricsScreen
                    anchors.fill: parent
                    z: 5
                    // fade + slight zoom in/out instead of popping
                    visible: opacity > 0
                    opacity: win.lyricsMode ? 1 : 0
                    scale: win.lyricsMode ? 1 : 0.97
                    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    track: player.current
                    lyrics: win.lyrics
                    loadingLyrics: win.loadingLyrics
                    playing: media.playbackState === MediaPlayer.PlayingState
                    position: player.pendingSeek > 0 ? player.pendingSeek : media.position
                    duration: media.duration
                    shuffle: player.shuffle; repeat: player.repeat; volume: win.userVolume
                    backdrop: win.backdrop; colors: win.coverColors
                    onToggle: playerBar.toggle()
                    onNext: player.next()
                    onPrev: player.prev()
                    onSeek: (ms) => player.seekTo(ms)
                    onToggleShuffle: player.toggleShuffle()
                    onCycleRepeat: player.cycleRepeat()
                    onVolumeMoved: (v) => win.setVolume(v)
                    onClose: win.lyricsMode = false
                    onEditLyrics: lyricsEditor.openWith(player.current, win.lyrics)
                    onStarToggled: (t, s) => win.onStar(t, s)
                    onAddToPlaylist: (t, x, y) => { if (t && !t.free) trackMenu.openPlaylistsAt(t, x, y, sidebar.playlists) }
                    onRefetchLyrics: { if (!player.current) return; win.lyrics = { kind: "none" }; win.loadingLyrics = true; library.refetchLyrics(player.current.id) }
                }

                // Empty state (AdwStatusPage)
                Column {
                    anchors.centerIn: parent
                    visible: nav.page === "albums" && albumGrid.count === 0
                    spacing: 10
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "folder-music"; size: 96; color: Theme.dimFg }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: library.scanning ? "Indexando sua biblioteca…" : "Nenhuma música encontrada"; color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize - 2; font.weight: Theme.titleWeight }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: library.scanning ? library.status : library.libraryDir; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                }
            }
        }

        PlayerPanel {
            id: playerPanel
            visible: win.panelDocked
            width: Math.min(400, Math.max(300, win.width * 0.27))
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            track: player.current
            playing: media.playbackState === MediaPlayer.PlayingState
            position: player.pendingSeek > 0 ? player.pendingSeek : media.position
            duration: media.duration
            shuffle: player.shuffle; repeat: player.repeat; volume: win.userVolume
            queue: player.queue; queueIndex: player.index
            autoplay: win.autoplay
            backdrop: win.prefs.panelcolors ? win.backdrop : ""
            colors: win.prefs.panelcolors ? win.coverColors : []
            lyrics: win.lyrics
            loadingLyrics: win.loadingLyrics
            onToggle: playerBar.toggle()
            onNext: player.next()
            onPrev: player.prev()
            onSeek: (ms) => player.seekTo(ms)
            onToggleShuffle: player.toggleShuffle()
            onCycleRepeat: player.cycleRepeat()
            onVolumeMoved: (v) => win.setVolume(v)
            onJump: (i) => player.jump(i)
            onRemoveAt: (i) => player.removeAt(i)
            onMoveItem: (f, t) => player.move(f, t)
            onAutoplayToggled: (on) => win.setPref("autoplay", on)
            onOpenLyrics: win.lyricsMode = true
            onClose: { win.panelOpen = false; library.setSetting("panel", "0") }
            onStarToggled: (t, s) => win.onStar(t, s)
            onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
            // the window's close button lives in the panel's corner when it is docked
            windowControls: win.csd && !Theme.apple
            allWindowButtons: win.prefs.winbuttons === "all"
            window: win
            MouseArea { anchors { left: parent.left; right: parent.right; top: parent.top } height: 46; z: -1; onPressed: win.startSystemMove(); onDoubleClicked: win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized() }
        }

        PlayerBar {
            id: playerBar
            // Kept only for its toggle(): the player lives in the right panel.
            visible: false
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            track: player.current
            playing: media.playbackState === MediaPlayer.PlayingState
            position: player.pendingSeek > 0 ? player.pendingSeek : media.position
            duration: media.duration
            shuffle: player.shuffle
            repeat: player.repeat
            volume: win.userVolume
            onToggle: playing ? media.pause() : (player.current ? media.play() : null)
            onNext: player.next()
            onPrev: player.prev()
            onSeek: (ms) => player.seekTo(ms)
            onExpand: { if (win.wide) { win.panelOpen = true; library.setSetting("panel", "1") } else win.lyricsMode = true }
            onLyrics: win.lyricsMode = !win.lyricsMode
            onToggleShuffle: player.toggleShuffle()
            onCycleRepeat: player.cycleRepeat()
            onVolumeMoved: (v) => win.setVolume(v)
        }

        // AdwToast
        Rectangle {
            id: toast
            z: 100
            property string text: ""
            function show(t) { text = t; opacity = 1; toastTimer.restart() }
            anchors { horizontalCenter: content.horizontalCenter; bottom: playerBar.visible ? playerBar.top : parent.bottom; bottomMargin: 16 }
            width: toastText.implicitWidth + 40; height: 40; radius: Theme.toastRadius
            color: Theme.toastBg
            opacity: 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Text { id: toastText; anchors.centerIn: parent; text: toast.text; color: Theme.toastFg; font.family: Theme.font; font.pointSize: Theme.fontSize }
            Timer { id: toastTimer; interval: 2600; onTriggered: toast.opacity = 0 }
        }
    }

    LyricsEditor {
        id: lyricsEditor
        parent: frame
        anchors.fill: parent
        anchors.bottomMargin: playerBar.visible ? playerBar.height : 0
        z: 50
        visible: false
        position: media.position
        playing: media.playbackState === MediaPlayer.PlayingState
        onSeek: (ms) => player.seekTo(ms)
        onTogglePlay: playerBar.toggle()
        onSave: (text, synced, sidecar) => {
            library.saveLyrics(track.id, text, synced, sidecar)
            toast.show(synced ? "Letra sincronizada salva" : "Letra salva")
        }
        onPublish: library.publishLyrics(track.id)
        onClose: visible = false
    }
    Connections {
        target: library
        function onLyricsPublished(trackId, ok, message) { lyricsEditor.publishing = false; toast.show(message) }
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
        onGoToAlbum: (t) => { win.lyricsMode = false; nav.openAlbumById(t.albumId) }
    }
    TextPrompt { id: prompt }
    Timer { id: volumeSave; interval: 600; onTriggered: library.setSetting("volume", String(win.userVolume)) }
    ImportDialog {
        id: importDialog
        onImportPath: (path) => library.importPath(path)
        onPickRequested: (directory) => library.pickPath("import", directory ? "Escolha a pasta exportada" : "Escolha o arquivo exportado", directory)
    }
    AppMenu {
        id: appMenu
        onPreferences: prefsDialog.open()
        onChooseFolder: { foldersDialog.dirs = JSON.parse(library.libraryDirsJson()); foldersDialog.open() }
        onRescan: library.changeLibraryDir(library.libraryDir)
        onImportPlaylists: importDialog.start()
        onShortcuts: prompt.info("Atalhos de teclado",
            "Espaço: tocar ou pausar\nCtrl+,: preferências\nCtrl+→ / Ctrl+←: próxima / anterior\nCtrl+F: buscar\nCtrl+L: letra em tela cheia\nEsc: voltar\nCtrl+Q: sair\n\nNo editor de letras: Enter marca o verso, Backspace desfaz, ← volta 5 s")
        onAbout: prompt.info("Arara Music 0.7",
            "Player de música leve em Rust e Qt, com temas GNOME, Apple, Android e Windows.\nLetras do LRCLIB, servidores Navidrome e Jellyfin.\n\nLicença GPL-3.0 · ícones do tema Adwaita")
    }
    PreferencesDialog {
        id: prefsDialog
        parent: frame
        anchors.fill: parent
        prefs: win.prefs
        setFn: win.setPref
        onChooseFolders: { foldersDialog.dirs = JSON.parse(library.libraryDirsJson()); foldersDialog.open() }
        onRescan: { library.changeLibraryDir(library.libraryDir); toast.show("Reindexando a biblioteca…") }
        onResetAll: prompt.confirm("Restaurar as preferências?", "Tema, cores, reprodução e letras voltam ao padrão.", "Restaurar", function () { win.resetPrefs() })
    }
    FolderDialog {
        id: folderDialog
        property bool adding: false
        title: adding ? "Adicionar pasta de músicas" : "Escolha a pasta de músicas"
        currentFolder: "file://" + library.libraryDir
        options: FolderDialog.ShowDirsOnly
        onAccepted: {
            var p = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
            if (adding) { library.addLibraryDir(p); foldersDialog.dirs = JSON.parse(library.libraryDirsJson()) }
            else library.changeLibraryDir(p)
        }
    }
    FoldersDialog {
        id: foldersDialog
        onAddRequested: library.pickPath("addlibrary", "Adicionar pasta de músicas", true)
        onRemoveRequested: (d) => prompt.confirm("Tirar “" + d + "” da biblioteca?", "As músicas dessa pasta saem da biblioteca. Nenhum arquivo é apagado.", "Tirar", function () {
            library.removeLibraryDir(d); foldersDialog.dirs = JSON.parse(library.libraryDirsJson())
        })
    }
    AddServerDialog {
        id: addServer
        onSubmit: (kind, url, user, password) => library.addServer(kind, url, user, password)
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

    onClosing: player.save()

    Shortcut { sequence: "Space"; enabled: !search.activeFocus && !prompt.visible && !lyricsEditor.visible && !addServer.visible && !importDialog.visible; onActivated: playerBar.toggle() }
    Shortcut { sequence: "Ctrl+F"; onActivated: nav.go("songs") }
    Shortcut { sequence: "Ctrl+Right"; onActivated: player.next() }
    Shortcut { sequence: "Ctrl+Left"; onActivated: player.prev() }
    Shortcut { sequence: "Ctrl+L"; onActivated: win.lyricsMode = !win.lyricsMode }
    Shortcut { sequence: "Escape"; onActivated: { if (prefsDialog.visible) prefsDialog.close(); else if (lyricsEditor.visible) lyricsEditor.visible = false; else if (win.lyricsMode) win.lyricsMode = false; else if (nav.history.length) nav.back() } }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.close() }
    Shortcut { sequence: "Ctrl+,"; onActivated: prefsDialog.visible ? prefsDialog.close() : prefsDialog.open() }
}
