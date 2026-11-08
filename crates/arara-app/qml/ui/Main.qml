import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtMultimedia
import QtQuick.Dialogs
import AraraStyle
import io.github.arara
import AraraCypher as Cypher

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
    // The lyrics screen and the study mode (Estudar) have their own controls and use the full width.
    readonly property bool panelDocked: !lyricsMode && !practicing && !(nav.page === "studies" && prefs.hidestudypanel)
    property bool lyricsMode: false
    // ---------- preferences ----------
    // Every setting lives here, typed; stored as "pref:<key>" strings
    // (booleans as "1"/"0", lists and maps as JSON).
    readonly property var prefDefaults: ({
        theme: "gnome", scheme: "system", accent: "theme", panelcolors: true,
        tilesize: "medium", fontscale: 1.0, compact: false, reducemotion: false,
        replaygain: true, rgmode: "track", preamp: 0, autoplay: false, restore: true, remaining: true,
        autolyrics: true, lrcbeside: true, lyricspanel: true, duets: true, lyricsscale: 1, lyricsoffset: 0,
        explicit: true, explicitlyrics: true, rate: 1.0, onlineinfo: true, infoprefetch: true, infofiles: true, listening: true, motioncovers: false,
        // transitions between songs (see Decks.qml and the `xf` object below)
        xfmode: "crossfade", xfdur: 6, xfcurve: "equal", xftrim: true, xfalbum: true,
        xfmanual: true, xfpause: true, xfbeat: false, xfloud: true, xflatency: 160,
        hidden: [], collapsed: ({ categories: true }), winbuttons: "close",
        edittags: true, hidedupes: true,
        hidestudypanel: false   // aba Estudos sem o player do lado
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
        for (var k in prefDefaults) if (k !== "hidden" && k !== "collapsed") setPref(k, prefDefaults[k])
        toast.show("Preferências restauradas")
    }
    readonly property bool autoplay: prefs.autoplay
    readonly property bool trackListening: prefs.listening
    readonly property bool coverAccent: prefs.accent === "cover"
    readonly property bool autoLyrics: prefs.autolyrics
    property var lyrics: ({ kind: "none" })
    // ---------- favourite excerpt ----------
    // One per song, marked on the lyrics screen; stored as "pref:excerpt:<id>"
    // = {"s": ms, "e": ms}. `excerptRev` re-reads it after a change.
    property int excerptRev: 0
    readonly property var excerpt: {
        excerptRev
        var t = player.current
        if (!t || t.id === undefined || t.free) return null
        try {
            var x = JSON.parse(library.setting("excerpt:" + t.id, "null"))
            return x && x.e > x.s ? x : null
        } catch (err) { return null }
    }
    function setExcerpt(t, s, e) {
        if (!t) return
        if (e > s) {
            library.setSetting("excerpt:" + t.id, JSON.stringify({ s: s, e: e }))
            toast.show("Trecho preferido salvo: " + fmtMs(s) + " – " + fmtMs(e))
        } else {
            library.setSetting("excerpt:" + t.id, "null")
            excerptPlay.stop(false)
            toast.show("Trecho preferido removido")
        }
        excerptRev++
    }
    function fmtMs(ms) {
        var t = Math.max(0, Math.round(ms / 1000))
        return Math.floor(t / 60) + ":" + ("0" + (t % 60)).slice(-2)
    }
    property bool loadingLyrics: false
    // ---------- Estudos (Arara Cypher) ----------
    // Modo Estudar: a cifra da música tocando no player. Enquanto estuda, o
    // fim da música não passa para a próxima e as transições ficam paradas.
    readonly property bool practicing: nav.page === "practice" && !!practiceSheet
    property var practiceSheet: null
    readonly property bool currentHasSheet: {
        CypherLibrary.revision
        var t = player.current
        return !!t && !t.free && CypherLibrary.hasSheet(t.title || "", t.artist || "")
    }
    property bool practiceBacking: true      // som da música (desligado = treino sem a gravação)
    property real rateBeforePractice: -1
    // Cifra do Arara Cypher para uma faixa, ou null.
    function sheetFor(t) {
        if (!t || t.free) return null
        var j = CypherLibrary.sheetFor(t.title || "", t.artist || "")
        return j ? JSON.parse(j) : null
    }
    // Exemplos do Cypher contam como cifra (lidos uma vez, é só texto).
    Component.onCompleted: {
        CypherLibrary.setExamples(JSON.stringify(Cypher.Examples.visibleSongs))
        Cypher.Examples.trackFinder = win.trackForSheet
    }
    Connections {
        target: Cypher.Examples
        function onStudyRequested(track, sheet) { win.studyTrack(track, sheet) }
    }
    // Faixa da biblioteca que combina com a cifra (mesma regra de título e artista).
    function trackForSheet(sheet) {
        if (!sheet || !sheet.title) return null
        CypherLibrary.revision   // relê quando a biblioteca de cifras muda
        var found = JSON.parse(library.searchJson(sheet.title))
        for (var i = 0; i < found.length; ++i)
            if (CypherMusic.sheetMatches(sheet.title, sheet.artist || "", found[i].title || "", found[i].artist || "")) return found[i]
        return null
    }
    function studyTrack(t, chosen) {
        var sheet = chosen || sheetFor(t)
        if (!sheet) {
            // Sem cifra: abre o editor do Cypher já com o nome da música.
            nav.root("studies")
            studiesLoader.active = true
            Qt.callLater(function () { if (studiesLoader.item) studiesLoader.item.newSheetFor(t.title, t.artist) })
            toast.show("Ainda não tem cifra para “" + t.title + "”: escreva uma no editor")
            return
        }
        practiceSheet = sheet
        practiceBacking = true
        if (!player.current || player.current.id !== t.id) {
            // Entra logo depois da música atual e abre pausada, sem mexer no resto da fila.
            if (!player.current) { player.queue = [t]; player.index = 0 }
            else { var q = player.queue.slice(); q.splice(player.index + 1, 0, t); player.queue = q; player.index++ }
            player.start(false)
        }
        win.lyricsMode = false
        nav.go("practice")
        nav.section = "practice"
    }
    // "Editar cifra" no modo Estudar: abre a cifra no editor da aba Estudos.
    function editStudySheet(sh) {
        nav.root("studies")
        studiesLoader.active = true
        if (studiesLoader.item) studiesLoader.item.editSheet(sh)
    }
    function leavePractice() {
        practiceBacking = true
        if (rateBeforePractice > 0) { win.setRate(rateBeforePractice); rateBeforePractice = -1 }
    }
    Connections { target: nav; function onPageChanged() { if (nav.page !== "practice") win.leavePractice() } }
    // Blurred cover + sampled colours of the current track, for backgrounds.
    property string backdrop: ""
    property var coverColors: []
    function useAlbumCover(id, path) {
        library.setAlbumCover(id, path)
        toast.show("Capa do álbum trocada")
    }
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
    readonly property real gainFactor: trackGain(player.current)
    // ReplayGain from tags; without tags, the loudness measured for transitions
    // (EBU R128, aiming at -18 LUFS like ReplayGain 2).
    function trackGain(t) {
        if (!replayGain || !t) return 1.0
        var has = function (x) { return x !== undefined && x !== null }
        var g = prefs.rgmode === "album" ? (has(t.albumGain) ? t.albumGain : t.gain) : (has(t.gain) ? t.gain : t.albumGain)
        if (!has(g) && prefs.xfloud) {
            var an = xf.analyses[t.id]
            if (an && an.lufs !== null && an.lufs !== undefined) g = -18 - Number(an.lufs)
        }
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
    Binding { target: Prefs; property: "showExplicit"; value: win.prefs.explicit }
    Binding { target: Prefs; property: "motionCovers"; value: win.prefs.motioncovers && win.prefs.onlineinfo }
    Binding { target: Prefs; property: "explicitLyrics"; value: win.prefs.explicitlyrics }
    Binding { target: Prefs; property: "playbackRate"; value: Prefs.clampRate(Number(win.prefs.rate) || 1) }
    Connections {
        target: Prefs
        function onRequestRate(r) { win.setRate(r) }
        function onPlaybackRateChanged() { decks.applyRate() }
    }
    function setRate(r) {
        r = Prefs.clampRate(r)
        if (Math.abs(r - Prefs.playbackRate) < 0.001) return
        win.setPref("rate", r)
    }

    // Everything that talks to the system (scan, D-Bus, audio devices, the
    // restored song) starts only after the first frame is on screen, so the
    // window always shows up even if one of those is slow.
    property bool servicesStarted: false
    function startServices() {
        if (servicesStarted) return
        servicesStarted = true
        library.startServices()
        if (nav.page === "home") homePage.reload()
        if (win.prefs.restore) { library.heartbeat("restaurando a última música"); player.restore() }
        library.heartbeat("pronto")
    }
    onFrameSwapped: if (!servicesStarted) Qt.callLater(startServices)
    Timer { interval: 1500; running: !win.servicesStarted; onTriggered: win.startServices() }
    // Freeze reporter: see watchdog.rs.
    Timer { interval: 1000; running: true; repeat: true; onTriggered: library.heartbeat("") }

    Library {
        id: library
        Component.onCompleted: {
            library.open()
            win.userVolume = Number(library.setting("volume", "1"))
            win.loadPrefs()
            win.panelOpen = library.setting("panel", "1") === "1"
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
            if (purpose === "trackcover") trackEdit.coverPicked(path)
            else if (purpose === "library") library.changeLibraryDir(path)
            else if (purpose === "addlibrary") { library.addLibraryDir(path); foldersDialog.dirs = JSON.parse(library.libraryDirsJson()) }
            else if (purpose.indexOf("cover:") === 0) win.useAlbumCover(Number(purpose.slice(6)), path)
            else importDialog.pickedPath(path)
        }
        onPickerUnavailable: (purpose, directory) => {
            if (purpose === "trackcover") { coverFileDialog.open(); return }
            if (purpose === "library" || purpose === "addlibrary") { folderDialog.adding = purpose === "addlibrary"; folderDialog.open() }
            else if (purpose.indexOf("cover:") === 0) { coverDialog.albumId = Number(purpose.slice(6)); coverDialog.open() }
            else importDialog.fallback(directory)
        }
        onServerAdded: (ok, message) => { addServer.finished(ok, message); if (ok) toast.show(message) }
        onPlaylistsChanged: { sidebar.playlists = JSON.parse(library.playlistsJson()); if (nav.page === "playlist") nav.refresh() }
        onLyricsReady: (trackId, json) => {
            // qint64 arrives as an object in JS; compare as numbers
            if (player.current && player.current.id === Number(trackId)) { win.lyrics = JSON.parse(json); win.loadingLyrics = false }
            // Lyrics just fetched may reveal an explicit song: refresh its badge.
            var e = library.explicitOf(Number(trackId))
            if (e !== (Prefs.explicitOverride[Number(trackId)] !== undefined ? Prefs.explicitOverride[Number(trackId)] : -1)) Prefs.setExplicit(trackId, e)
        }
        onAnalysisReady: (trackId, json) => xf.store(Number(trackId), json)
        onMediaCommand: (cmd, arg) => {
            var us = Number(arg)
            switch (cmd) {
            case "play": player.resume(); break
            case "pause": player.pause(); break
            case "playpause": playerBar.toggle(); break
            case "stop": decks.stopAll(); break
            case "next": player.next(); break
            case "previous": player.prev(); break
            case "seek": player.seekTo(media.position + us / 1000); break
            case "setposition": player.seekTo(us / 1000); break
            case "setrate": win.setRate(us / 1000); break
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

        property int failures: 0
        // A new queue keeps what already played from the old one, so "previous"
        // still goes back after starting a song from a list, a station…
        function playList(list, i) {
            if (current && !sameList(queue, list)) {
                var p = played.concat(queue.slice(Math.max(0, index - 99), index + 1))
                // the song about to play is not "before" itself
                while (p.length && list[i] && p[p.length - 1].id === list[i].id) p.pop()
                played = p.slice(-100)
            }
            queue = list.slice(); index = i; shuffle = false; start(true)
        }
        // `mixed`: the decks already started this song (automatic transition).
        function start(autoplay, mixed) {
            if (!current) { decks.stopAll(); return }
            listen.restart()
            if (!mixed) {
                var from = xf.startFor(current)
                // A song changed by hand while one is playing: short crossfade, if enabled.
                if (autoplay && xf.manualMs() > 0 && media.playbackState === MediaPlayer.PlayingState && !restoring)
                    decks.crossfade(current, from, xf.manualMs(), true)
                else decks.load(current, from, autoplay)
            }
            if (autoplay) library.recordPlay(current.id)
            xf.prepare()
            win.lyrics = { kind: "none" }
            win.loadingLyrics = true
            library.requestLyrics(current.id)
            save()
        }
        function next() {
            if (repeat === "one" && media.mediaStatus === MediaPlayer.EndOfMedia) { listen.restart(); decks.load(current, 0, true); return }
            if (index + 1 < queue.length) { index++; start(true) }
            else if (repeat === "all" && queue.length > 0) { index = 0; start(true) }
            else if (win.autoplay && current && extendAutoplay()) { index++; start(true) }
        }
        // Songs played before the current queue started (oldest first).
        property var played: []
        property double lastRewind: 0
        // Previous: 3 s into the song it starts it over; a second press (or a press
        // near the start) goes to the song before. The start is where the song
        // really begins (trimmed intro), and a press right after a rewind counts
        // as "at the start" even if the backend still reports the old position.
        function prev() {
            if (!current) return
            var pos = media.position - xf.startFor(current)
            var justRewound = Date.now() - lastRewind < 3000
            while (played.length && played[played.length - 1].id === current.id) played = played.slice(0, -1)
            var hasBefore = index > 0 || played.length > 0 || (repeat === "all" && queue.length > 1)
            if ((pos > 3000 && !justRewound) || !hasBefore) { lastRewind = Date.now(); seekTo(xf.startFor(current)); return }
            lastRewind = 0
            if (index > 0) { index--; start(true); return }
            if (played.length > 0) {
                var t = played[played.length - 1]
                played = played.slice(0, -1)
                queue = [t].concat(queue); index = 0
                start(true)
                return
            }
            index = queue.length - 1; start(true)
        }
        // Same songs in the same order (a double click starts one list twice).
        function sameList(a, b) {
            if (a.length !== b.length) return false
            for (var k = 0; k < a.length; k++) if (a[k].id !== b[k].id) return false
            return true
        }
        function jump(i) { index = i; start(true) }
        // The song that would play after this one, without changing anything
        // (null at the end of the queue, or when repeating one song).
        function peekNext() {
            if (repeat === "one" || !current) return null
            if (index + 1 < queue.length) return queue[index + 1]
            if (repeat === "all" && queue.length > 0) return queue[0]
            return null
        }
        // Automatic transition: move to the next song; the decks already play it.
        function advanceMixed() {
            if (index + 1 < queue.length) index++
            else if (repeat === "all" && queue.length > 0) index = 0
            else return
            start(true, true)
        }
        function togglePlay() { if (media.playbackState === MediaPlayer.PlayingState) pause(); else resume() }
        function pause() { decks.pause(win.prefs.xfpause ? 220 : 0) }
        function resume() { if (current) decks.resume(win.prefs.xfpause ? 300 : 0) }
        // Autoplay: when the queue runs out, append tracks like the last ones.
        function extendAutoplay() {
            var recent = queue.slice(-200).map(function (t) { return t.id })
            var more = JSON.parse(library.autoplayJson(current.id, JSON.stringify(recent), 25))
            if (more.length === 0) return false
            queue = queue.concat(more); save()
            toast.show("Reprodução automática: " + more.length + " músicas na fila")
            return true
        }
        function seekTo(ms) { decks.finish(); media.position = Math.max(0, ms); library.mprisPosition(media.position, true) }

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
            played = played.filter(function (t) { return !pred(t) })
            var cur = current, q = queue.filter(function (t) { return !pred(t) })
            if (q.length === queue.length) return
            if (cur && pred(cur)) { decks.stopAll(); queue = q; index = q.length ? 0 : -1; if (current) start(false) }
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

    // Two players so songs can fade into each other; `media` is the one playing now.
    Decks {
        id: decks
        // Qt picks the default output only once, at startup. Follow the output chosen in
        // GNOME (headset, HDMI, line out…) whenever it changes, even mid-song.
        device: sysAudio.defaultAudioOutput
        volume: win.userVolume * (win.practicing && !win.practiceBacking ? 0 : 1)
        gainFor: function (t) { return win.trackGain(t) }
        curve: win.prefs.xfcurve
        onRateApplied: (r) => library.mprisRate(r)
        Component.onCompleted: library.mprisRate(Prefs.playbackRate)
        // A missing file or unreachable server: say so and move on, but don't
        // spin through a whole queue of broken tracks.
        onFailed: (message) => {
            if (!player.current) return
            toast.show("Não foi possível tocar “" + player.current.title + "”")
            if (++player.failures < 3) player.next()
        }
        // Estudando: a música acaba e volta para o começo, pausada.
        onEndOfMedia: win.practicing ? decks.load(player.current, 0, false) : player.next()
        onActiveLoaded: applyPendingSeek()
        onActiveStateChanged: {
            if (!media) return
            if (media.playbackState === MediaPlayer.PlayingState) player.failures = 0
            applyPendingSeek(); mpris.push()
            library.setPlaying(media.playbackState === MediaPlayer.PlayingState)
        }
        // GStreamer only accepts a seek once the stream is seekable (or playing).
        function applyPendingSeek() {
            if (player.pendingSeek > 0 && media.seekable) { media.position = player.pendingSeek; player.pendingSeek = -1 }
        }
    }
    readonly property MediaPlayer media: decks.active
    readonly property bool debugXf: Qt.application.arguments.indexOf("--debug-transitions") >= 0
    Connections { target: decks.active; function onSeekableChanged() { decks.applyPendingSeek() } }

    // ---------- transitions ----------
    // Plans when and how the next song comes in. Methods, from open-source players:
    //  gapless (no gap, next song preloaded), crossfade with a chosen curve (Strawberry,
    //  Audacious), silence trimming (Audacious, Mixxx "Skip Silence"), smart mix that
    //  overlaps only the quiet fade-out/fade-in parts (MPD MixRamp), beat alignment
    //  (Mixxx Auto DJ, simplified: no time-stretch) and loudness matching (ReplayGain 2).
    QtObject {
        id: xf
        property var analyses: ({})        // track id → analysis (or null when unavailable)
        property var requested: ({})
        readonly property string mode: win.prefs.xfmode
        function store(id, json) {
            var a = {}; for (var k in analyses) a[k] = analyses[k]
            try { a[id] = JSON.parse(json) } catch (e) { a[id] = null }
            analyses = a
        }
        function want(t) {
            if (!t || requested[t.id] || t.remote) return
            requested[t.id] = true
            library.requestAnalysis(t.id)
        }
        // Analyse the current song and the next one (only these two: decoding costs CPU).
        function prepare() {
            if (mode === "off" && !(win.prefs.replaygain && win.prefs.xfloud)) return
            want(player.current)
            want(player.peekNext())
        }
        function trimOn() { return win.prefs.xftrim && mode !== "off" }
        // Where a song starts when played (skips leading silence).
        function startFor(t) {
            var a = t ? analyses[t.id] : null
            return trimOn() && a && a.intro_ms > 300 ? a.intro_ms : 0
        }
        function manualMs() {
            if (!win.prefs.xfmanual || mode === "off" || mode === "gapless") return 0
            return Math.min(2000, win.prefs.xfdur * 1000)
        }
        function sameAlbum(a, b) {
            // Consecutive songs of one album (not a shuffle that happened to land there):
            // albums that flow into the next track (live, concept albums) stay intact.
            return win.prefs.xfalbum && !player.shuffle && a.albumId !== undefined && a.albumId !== null
                && a.albumId >= 0 && a.albumId === b.albumId
        }
        function beatAt(a, t, after) {
            var p = 60000 / a.bpm, k = Math.floor((t - a.beat_ms) / p)
            var x = a.beat_ms + k * p
            return after && x < t ? x + p : x
        }
        // → { at: position in the current song to start the next, start: where the next
        //     starts, dur: fade length (0 = gapless switch), cut: stop the old one at once }
        function plan(a, b) {
            var A = analyses[a.id], B = analyses[b.id]
            var durA = A ? A.duration_ms : (media.duration > 0 ? media.duration : a.duration)
            var durB = B ? B.duration_ms : b.duration
            if (!durA) return null
            var trim = trimOn()
            var endA = trim && A ? A.outro_ms : durA
            var startB = trim && B && B.intro_ms > 300 ? B.intro_ms : 0
            // GStreamer takes a moment (~0.1 s, measured) before a started song is heard:
            // gapless switches start that much early, beat-aligned mixes skip that much in.
            var lead = Math.max(0, Number(win.prefs.xflatency))
            if (mode === "gapless" || sameAlbum(a, b)) {
                // Albums that flow into the next track (live, concept albums) stay intact.
                if (sameAlbum(a, b)) { endA = durA; startB = 0 }
                return { at: endA - lead, start: startB, dur: 0, cut: endA < durA - 100 }
            }
            var user = win.prefs.xfdur * 1000
            var cap = Math.max(1000, Math.min(durA, durB || durA) / 3)
            var d = Math.min(user, cap), at = endA - d, aligned = false
            if (mode === "smart" && A && B) {
                // MixRamp: the next song reaches full level just as this one drops below it.
                var head = Math.max(0, B.ramp_in_ms - startB)
                at = A.ramp_out_ms - head
                var maxD = Math.min(Math.max(user * 1.5, 3000), cap)
                if (endA - at > maxD) at = endA - maxD
                // abrupt endings still get a short blend (half the chosen duration)
                var minD = Math.min(maxD, Math.max(1000, user / 2))
                if (endA - at < minD) at = endA - minD
                // Beat alignment when the tempos match (or are double/half), within 4%.
                if (win.prefs.xfbeat && A.bpm && B.bpm && A.beat_ms !== null && B.beat_ms !== null) {
                    var r = A.bpm / B.bpm
                    var close = [0.5, 1, 2].some(function (m) { return Math.abs(r / m - 1) < 0.04 })
                    if (close) {
                        at = beatAt(A, at, false)
                        startB = Math.max(startB, B.beat_ms)
                        aligned = true
                    }
                }
                d = endA - at
            }
            if (aligned) startB += lead
            return { at: at, start: startB, dur: d, cut: true, beat: aligned }
        }
        property real nextAt: -1     // position where the next transition starts
        function tick() {
            var a = player.current, b = player.peekNext()
            if (!a) return
            if (!b && win.autoplay && player.index + 1 >= player.queue.length) {
                // Autoplay: fill the queue early enough to mix into its first song.
                var left = (media.duration - media.position) / Math.max(0.25, Prefs.playbackRate)
                if (media.duration > 0 && left < (win.prefs.xfdur * 1000 * 1.5 + 10000) && player.extendAutoplay()) b = player.peekNext()
            }
            if (!b || decks.transitioning) { nextAt = -1; return }
            want(a); want(b)
            var p = plan(a, b)
            nextAt = p ? p.at : -1
            if (!p) return
            var rate = Math.max(0.25, Prefs.playbackRate)
            var wall = (p.at - media.position) / rate
            if (wall < 12000) decks.preload(b, p.start)
            if (media.position >= p.at && media.position > 500) {
                if (win.debugXf) console.log("transição", a.title, "→", b.title, JSON.stringify(p), "pos", media.position, "análises", !!analyses[a.id], !!analyses[b.id])
                decks.crossfade(b, p.start, p.dur, p.cut)
                player.advanceMixed()
            }
        }
    }
    Timer {
        // Faster near the transition point so switches land within a few ms.
        interval: xf.nextAt > 0 && xf.nextAt - media.position < 1500 ? 15 : 200
        repeat: true
        running: xf.mode !== "off" && media.playbackState === MediaPlayer.PlayingState && !win.practicing
        onTriggered: xf.tick()
    }

    // Listening time for the recap ("Retrospectiva"): only time actually heard
    // counts (pauses, seeks and skipped parts don't). Saved every 15 s, on track
    // change and on quit.
    Timer {
        id: listen
        property int forId: -1      // track the open listen belongs to
        property real listenId: 0
        property real pending: 0    // ms heard but not saved yet
        property real lastPos: -1
        property real lastTick: 0
        interval: 1000; repeat: true
        running: media.playbackState === MediaPlayer.PlayingState && win.trackListening
        onRunningChanged: if (!running) { lastPos = -1; flush() }
        onTriggered: {
            var t = player.current
            if (!t || !(t.id > 0)) return
            var now = Date.now()
            if (forId !== t.id) { flush(); forId = t.id; listenId = library.beginListen(t.id); lastPos = media.position; lastTick = now; return }
            // Count wall-clock time while the position moves forward; a jump
            // much bigger than the time passed is a seek and doesn't count.
            var d = media.position - lastPos, w = lastPos < 0 ? 0 : now - lastTick
            lastPos = media.position; lastTick = now
            if (d > 0 && w > 0 && d <= w * 1.5 + 2000) pending += Math.min(d, w, 5000)
            if (pending >= 15000) flush()
        }
        function flush() {
            if (listenId > 0 && pending > 0) library.addListenTime(listenId, Math.round(pending))
            pending = 0
        }
        // The same song again (repeat one, replay) is a new listen.
        function restart() { flush(); forId = -1; listenId = 0; lastPos = -1 }
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
        property string page: "home"
        property var album: null
        property var artist: null
        property var playlist: null
        property var server: null
        property var history: []
        property var group: null          // {kind, name} of the open genre/year/composer/folder
        property var trackInfo: null      // track whose info page is open
        property var tag: null            // {name, fromName, excludeArtist, area} of the open "Similares" page
        // Sub-pages always get a back button, even when reached with no history.
        readonly property bool canGoBack: history.length > 0 || page === "album" || page === "artist" || page === "group" || page === "trackinfo" || page === "tag" || page === "practice"
        // Sidebar entry the current view belongs to (an album opened from a server keeps "server").
        property string section: "home"

        // Snapshot of the current view, taken before a navigation changes it.
        function state() {
            return { page: page, section: section, album: album, artist: artist, playlist: playlist, server: server, group: group, trackInfo: trackInfo, tag: tag,
                     groupQuery: catSongs.baseFilter, groupTitle: catSongs.heading, groupSort: catSongs.sort }
        }
        function go(p, st) {
            // Reassign (not push) so bindings on history.length, like the back button, update.
            if (p !== page || p === "group" || p === "album" || p === "artist" || p === "trackinfo" || p === "tag") history = history.concat([st || state()])
            page = p; if (p === "songs") section = "songs"
            refresh()
            if (p === "songs") search.forceActiveFocus(); else if (search.activeFocus && search.text === "") win.contentItem.forceActiveFocus()
        }
        function back() {
            var h = history.length > 0 ? history[history.length - 1] : null
            history = history.slice(0, -1)
            if (!h) {
                // No history (e.g. restored state): go up to the parent listing.
                root(page === "group" && group ? group.kind : page === "tag" ? "genre" : page === "artist" ? "artists" : page === "trackinfo" ? "songs" : page === "practice" ? "studies" : page === "album" && section !== "album" ? section : "albums")
                return
            }
            win.lyricsMode = false
            if ((h.page === "group" || h.page === "added") && h.groupQuery !== undefined) catSongs.open(h.groupQuery, h.groupTitle, h.groupSort)
            if (h.page === "album" && h.album) { albumPage.tracks = JSON.parse(library.albumTracksJson(h.album.id)) }
            if (h.page === "artist" && h.artist) { artistPage.albums = JSON.parse(library.artistAlbumsJson(h.artist.id)) }
            if (h.page === "tag" && h.tag) win.loadTag(h.tag)
            tag = h.tag || null
            if (h.page === "trackinfo" && h.trackInfo) win.loadTrackInfo(h.trackInfo)
            trackInfo = h.trackInfo || null
            page = h.page; section = h.section || h.page; album = h.album; artist = h.artist; playlist = h.playlist; server = h.server; group = h.group || null; refresh()
        }
        function root(p) {
            win.lyricsMode = false; page = p; section = p; history = []; win.drawerOpen = false
            if (p === "added") { catSongs.open("", "Adicionadas recentemente", "added") }
            refresh()
            if (p === "songs") search.forceActiveFocus(); else if (search.activeFocus && search.text === "") win.contentItem.forceActiveFocus()
        }
        // Category entry (a genre, a year, a composer or a folder) → its songs.
        function openGroup(kind, g) {
            var q = kind === "year" ? "ano:" + g.key : kind === "folder" ? "pasta:\"" + g.key + "\"" : (kind === "genre" ? "genero:" : "compositor:") + "\"" + g.key + "\""
            var label = kind === "genre" ? "Gênero" : kind === "year" ? "Ano" : kind === "composer" ? "Compositor" : "Pasta"
            go("group")
            group = { kind: kind, name: g.name, label: label }
            section = kind
            catSongs.open(q, label + ": " + g.name, kind === "folder" ? "album" : "artist")
        }
        function rootPlaylist(p) { win.lyricsMode = false; playlist = p; page = "playlist"; section = "playlist"; history = []; win.drawerOpen = false; refresh() }
        function rootServer(sv) { win.lyricsMode = false; server = sv; page = "server"; section = "server"; history = []; win.drawerOpen = false; refresh() }
        function openAlbum(a) { var st = state(); album = a; albumPage.tracks = JSON.parse(library.albumTracksJson(a.id)); albumPage.contentY = 0; go("album", st) }
        function openAlbumById(id) {
            var a = albumGrid.albums.find(function (x) { return x.id === id })
            if (a) openAlbum(a)
        }
        function openArtist(a) { var st = state(); artist = a; artistPage.albums = JSON.parse(library.artistAlbumsJson(a.id)); artistPage.contentY = 0; go("artist", st) }
        // Genre chip of an About block → "Similares" page for that genre.
        function openTag(name, fromName, excludeArtist, area) {
            var st = state(); win.lyricsMode = false
            tag = { name: name, fromName: fromName || "", excludeArtist: excludeArtist === undefined ? -1 : excludeArtist, area: area || "" }
            win.loadTag(tag); go("tag", st)
        }
        function openArtistById(id) {
            var a = artistGrid.artists.find(function (x) { return x.id === id })
            if (a) openArtist(a)
        }
        function openTrackInfo(t) { var st = state(); win.lyricsMode = false; win.loadTrackInfo(t); trackInfo = t; infoPage.contentY = 0; go("trackinfo", st) }
        function openPlaylist(p) { var st = state(); playlist = p; go("playlist", st) }
        function openServer(s) { var st = state(); server = s; go("server", st) }
        function refresh() {
            if (page === "album" && album) {
                var al = albumGrid.albums.find(function (x) { return x.id === album.id })
                if (al) album = al
            }
            if (page === "server" && server) {
                var all = JSON.parse(library.serversJson())
                var sv = all.find(function (x) { return x.id === server.id })
                if (!sv) { root("albums"); return }
                server = sv
                serverPage.albums = JSON.parse(library.serverAlbumsJson(sv.id))
            }
            // The home page waits for the first frame (see startServices).
            if (page === "home" && win.servicesStarted) homePage.reload()
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
        readonly property string title: page === "home" ? "Início"
            : page === "album" && album ? album.title
            : page === "artist" && artist ? artist.name
            : page === "artists" ? "Artistas"
            : page === "starred" ? "Favoritas"
            : page === "recent" ? "Tocadas recentemente"
            : page === "mostplayed" ? "Mais tocadas"
            : page === "added" ? "Adicionadas recentemente"
            : page === "genre" ? "Gêneros" : page === "year" ? "Anos" : page === "composer" ? "Compositores" : page === "folder" ? "Pastas"
            : page === "group" && group ? group.name
            : page === "playlist" ? "Playlist"
            : page === "server" ? "Servidor"
            : page === "trackinfo" ? "Informações"
            : page === "tag" && tag ? "Similares"
            : page === "studies" ? "Estudos" : page === "practice" ? "Estudar"
            : page === "songs" ? "Músicas" : page === "recap" ? "" : "Álbuns"
    }

    // Now-playing panel → artist / album pages of the current track.
    function albumOf(t) { return t && t.albumId !== null && t.albumId !== undefined ? albumGrid.albums.find(function (x) { return x.id === t.albumId }) : null }
    function goToAlbumOf(t) {
        var a = albumOf(t)
        if (a) { win.lyricsMode = false; nav.openAlbum(a) } else toast.show("Álbum não encontrado na biblioteca")
    }
    function goToArtistOf(t) {
        if (!t) return
        var arts = artistGrid.artists
        var ar = artistByName(t.artist)
        if (!ar) { var a = albumOf(t); if (a && a.artistId) ar = arts.find(function (x) { return x.id === a.artistId }) }
        if (ar) { win.lyricsMode = false; nav.openArtist(ar) } else toast.show("Artista não encontrado na biblioteca")
    }
    // ---------- info pages ----------
    // Artist page: the "Sobre o artista" block lives in the page's left column.
    property string infoKey: ""          // "artist:<id>" the artist page shows
    function loadTrackInfo(t) {
        infoPage.info = JSON.parse(library.trackInfoJson(t.id))
        infoPage.online = null; infoPage.loading = true
        library.requestOnlineInfo("track", t.id, false)
    }
    property string albumInfoKey: ""
    // Album page: the "Sobre o álbum" block lives in the page itself.
    function loadAlbumAbout(force) {
        if (nav.page !== "album" || !nav.album) return
        var key = "album:" + nav.album.id
        if (key === win.albumInfoKey && !force) return
        win.albumInfoKey = key
        albumPage.aboutInfo = JSON.parse(library.albumInfoJson(nav.album.id))
        albumPage.aboutOnline = null
        albumPage.aboutOff = !win.prefs.onlineinfo
        albumPage.aboutLoading = win.prefs.onlineinfo
        library.requestOnlineInfo("album", nav.album.id, !!force)
    }
    function loadInfoBar(force) {
        loadAlbumAbout(force)
        if (nav.page !== "artist" || !nav.artist) return
        var key = "artist:" + nav.artist.id
        if (key === win.infoKey && !force) return
        win.infoKey = key
        artistPage.aboutInfo = JSON.parse(library.artistInfoJson(nav.artist.id))
        artistPage.aboutOnline = null
        artistPage.aboutOff = !win.prefs.onlineinfo
        artistPage.aboutLoading = win.prefs.onlineinfo
        library.requestOnlineInfo("artist", nav.artist.id, !!force)
    }
    // "Similares" page: library part now, MusicBrainz artists when they arrive.
    function loadTag(t) {
        tagPage.tag = t.name; tagPage.fromName = t.fromName
        tagPage.data = JSON.parse(library.tagJson(t.name, t.excludeArtist))
        tagPage.knownArtists = artistGrid.artists
        tagPage.online = null
        tagPage.onlineOff = !win.prefs.onlineinfo
        tagPage.onlineLoading = win.prefs.onlineinfo
        if (win.prefs.onlineinfo) library.requestTagOnline(t.name, t.area)
    }
    Connections { target: nav; function onPageChanged() { win.loadInfoBar(false) } function onArtistChanged() { win.loadInfoBar(false) } function onAlbumChanged() { win.loadInfoBar(false) } }
    Connections {
        target: library
        function onOnlineInfo(kind, id, json) {
            var data = JSON.parse(json); id = Number(id)
            if (kind === "track" && infoPage.info && infoPage.info.id === id) { infoPage.online = data; infoPage.loading = false }
            if (kind === "artist" && win.infoKey === kind + ":" + id) { artistPage.aboutOnline = data; artistPage.aboutLoading = false }
            if (kind === "album" && win.albumInfoKey === "album:" + id) { albumPage.aboutOnline = data; albumPage.aboutLoading = false }
        }
        function onTagOnline(tag, json) {
            if (tag !== tagPage.tag) return
            tagPage.online = JSON.parse(json); tagPage.onlineLoading = false
        }
    }
    // Exact name first, then the main artist of "A feat. B" / "A & B".
    function artistByName(name) {
        var n = String(name || "").toLowerCase()
        var hit = artistGrid.artists.find(function (x) { return x.name.toLowerCase() === n })
        if (hit) return hit
        var main = n.split(/\s+(?:feat\.?|ft\.|featuring|part\.|com|&|e|x)\s+|,\s*/)[0].trim()
        return artistGrid.artists.find(function (x) { return x.name.toLowerCase() === main })
    }
    function openArtistNamed(name) {
        var ar = artistByName(name)
        if (ar) { win.lyricsMode = false; nav.openArtist(ar) } else toast.show("“" + name + "” não está na sua biblioteca")
    }
    function copyText(text, msg) { clip.text = text; clip.selectAll(); clip.copy(); clip.text = ""; toast.show(msg) }
    function showLyricsOf(t) {
        if (!player.current) player.playList([t], 0)
        else if (player.current.id !== t.id) { var q = player.queue.slice(); q.splice(player.index + 1, 0, t); player.queue = q; player.next() }
        win.lyricsMode = true
    }
    function startStation(t) {
        var more = JSON.parse(library.autoplayJson(t.id, JSON.stringify([t.id]), 40))
        player.playList([t].concat(more), 0)
        toast.show("Estação de “" + t.title + "”: " + (more.length + 1) + " músicas")
    }
    TextEdit { id: clip; visible: false }
    function setVolume(v) { win.userVolume = v; volumeSave.restart(); mpris.push() }
    function saveSmart(q, sort, suggested) {
        prompt.ask("Salvar como playlist inteligente", "Ela se atualiza sozinha com as músicas que combinam com “" + q + "”.", suggested, "Salvar", function (name) {
            var id = Number(library.saveSmartPlaylist(-1, name, q, sort, 0))
            nav.rootPlaylist({ id: id, name: name, smart: true })
            toast.show("Playlist inteligente “" + name + "” criada")
        })
    }
    Connections { target: player; function onCurrentChanged() { win.refreshCoverLook() } }
    // Home page shuffle buttons: a few hundred random songs from the whole
    // library (or the favourites), with the shuffle button lit.
    function shuffleLibrary(kind) {
        var t = JSON.parse(library.shuffleJson(kind, 500))
        if (!t.length) { toast.show(kind === "starred" ? "Nenhuma favorita ainda" : "Nenhuma música na biblioteca"); return }
        player.playList(t, 0)
        player.unshuffled = t.slice(); player.shuffle = true; player.save()
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
            footer: library.scanning ? library.status : library.trackCount + " faixas · " + library.albumCount + " álbuns" + (library.lyricsProgress ? "\n" + library.lyricsProgress : "") + (library.infoProgress ? "\n" + library.infoProgress : "")
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
                    FlatButton { icon: "back"; visible: nav.canGoBack; onClicked: nav.back() }
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
                    // Aba Estudos: esconder ou mostrar o player do lado (fica lembrado).
                    FlatButton {
                        visible: nav.page === "studies"
                        icon: "sidebar"; checked: !win.prefs.hidestudypanel
                        tip: win.prefs.hidestudypanel ? "Mostrar o player" : "Esconder o player"
                        onClicked: win.setPref("hidestudypanel", !win.prefs.hidestudypanel)
                    },
                    FlatButton { id: menuButton; icon: "menu"; onClicked: appMenu.openUnder(menuButton) }
                ]
            }
            Timer { id: searchTimer; interval: 120; onTriggered: songs.search(search.text) }

            // A music folder can't be read (external disk locked or unplugged).
            // Its songs stay in the library; the app rescans when it comes back.
            Rectangle {
                id: diskBanner
                readonly property var missing: JSON.parse(library.missingDirs || "[]")
                readonly property bool shown: missing.length > 0
                anchors { left: parent.left; right: parent.right; top: header.bottom }
                height: shown ? Math.max(52, bannerText.implicitHeight + 20) : 0
                visible: shown
                color: Qt.rgba(Theme.destructive.r, Theme.destructive.g, Theme.destructive.b, Theme.dark ? 0.16 : 0.10)
                Icon { id: bannerIcon; anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter } name: "warning"; size: 16; color: Theme.destructive }
                Text {
                    id: bannerText
                    anchors { left: bannerIcon.right; leftMargin: 10; right: bannerButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    wrapMode: Text.Wrap
                    text: diskBanner.missing.length === 0 ? ""
                        : "Não consigo ler " + diskBanner.missing[0] + (diskBanner.missing.length > 1 ? " e mais " + (diskBanner.missing.length - 1) : "")
                          + ". Se for um disco externo, conecte ou desbloqueie no Arquivos; as músicas voltam sozinhas."
                    color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                }
                FlatButton {
                    id: bannerButton
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "Abrir no Arquivos"; color: Theme.hover
                    onClicked: library.openMissingDir(diskBanner.missing[0])
                }
            }
            Item {
                id: stack
                anchors { left: parent.left; right: parent.right; top: diskBanner.bottom; bottom: parent.bottom }
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

                HomePage {
                    id: homePage
                    anchors.fill: parent
                    visible: nav.page === "home"
                    trackCount: library.trackCount
                    albumCount: library.albumCount
                    scanning: library.scanning
                    playingId: player.current ? player.current.id : -1
                    onShuffle: (kind) => win.shuffleLibrary(kind)
                    onOpenAlbum: (a) => nav.openAlbum(a)
                    onPlayAlbum: (a) => { var t = JSON.parse(library.albumTracksJson(a.id)); if (t.length) player.playList(t, 0) }
                    onOpenArtist: (a) => nav.openArtist(a)
                    onPlay: (t, i) => player.playList(t, i)
                    onSeeAll: (p) => nav.root(p)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onStarToggled: (t, s) => win.onStar(t, s)
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
                ArtistPage {
                    id: artistPage
                    anchors.fill: parent
                    visible: nav.page === "artist"
                    artist: nav.artist
                    playingId: player.current ? player.current.id : -1
                    function allTracks() {
                        var out = []
                        for (var i = 0; i < albums.length; i++) out = out.concat(JSON.parse(library.albumTracksJson(albums[i].id)))
                        return out
                    }
                    onPlayAll: (shuffle) => {
                        var t = allTracks()
                        if (shuffle) for (var i = t.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var x = t[i]; t[i] = t[j]; t[j] = x }
                        player.playList(t, 0)
                    }
                    onOpenAlbum: (a) => nav.openAlbum(a)
                    onPlayTracks: (t, i) => player.playList(t, i)
                    onOpenLink: (url) => Qt.openUrlExternally(url)
                    onOpenFolder: (url) => Qt.openUrlExternally(url)
                    onOpenTag: (tag) => nav.openTag(tag, nav.artist ? nav.artist.name : "", nav.artist ? nav.artist.id : -1,
                                                    artistPage.aboutOnline && artistPage.aboutOnline.country ? artistPage.aboutOnline.country : "")
                    onRefreshAbout: win.loadInfoBar(true)
                }
                TagPage {
                    id: tagPage
                    anchors.fill: parent
                    visible: nav.page === "tag"
                    playingId: player.current ? player.current.id : -1
                    onOpenArtist: (a) => nav.openArtist(a)
                    onOpenAlbum: (a) => nav.openAlbum(a)
                    onPlay: (t, i) => player.playList(t, i)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onStarToggled: (t, s) => win.onStar(t, s)
                    onOpenLink: (url) => Qt.openUrlExternally(url)
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
                    onOpenLink: (url) => Qt.openUrlExternally(url)
                    onOpenFolder: (url) => Qt.openUrlExternally(url)
                    onRefreshAbout: win.loadAlbumAbout(true)
                    onOpenTag: (tag) => nav.openTag(tag, nav.album ? nav.album.artist || "" : "", nav.album && nav.album.artistId ? nav.album.artistId : -1, "")
                    onRefreshCover: (id) => { library.refreshAlbumCover(id); toast.show("Procurando a capa nos arquivos do álbum…") }
                    onChooseCover: (id) => library.pickPath("cover:" + id, "Escolha a imagem da capa", false)
                }
                // Aba Estudos: o Arara Cypher inteiro. Só carrega na primeira visita.
                Loader {
                    id: studiesLoader
                    anchors.fill: parent
                    visible: nav.page === "studies"
                    active: false
                    onVisibleChanged: if (visible) active = true
                    sourceComponent: Cypher.StudiesPage {}
                }
                Loader {
                    id: practiceLoader
                    anchors.fill: parent
                    visible: nav.page === "practice"
                    active: nav.page === "practice" && !!win.practiceSheet
                    sourceComponent: Cypher.PracticePage {
                        track: player.current
                        sheet: win.practiceSheet
                        position: media.position
                        duration: media.duration > 0 ? media.duration : (player.current ? player.current.duration || 0 : 0)
                        playing: media.playbackState === MediaPlayer.PlayingState
                        loading: media.mediaStatus === MediaPlayer.LoadingMedia
                        lyrics: win.lyrics
                        lyricsLoading: win.loadingLyrics
                        rate: Prefs.playbackRate
                        backing: win.practiceBacking
                        store: ({ get: function (k, d) { return library.setting(k, d) }, set: function (k, v) { library.setSetting(k, v) } })
                        onSeek: (ms) => player.seekTo(ms)
                        onTogglePlay: player.togglePlay()
                        onRequestRate: (r) => { if (win.rateBeforePractice < 0) win.rateBeforePractice = Prefs.playbackRate; win.setRate(r) }
                        onRequestBacking: (on) => win.practiceBacking = on
                        // O Loader do Estudar some ao trocar de página: quem abre o editor é a janela.
                        onEditSheet: (sh) => Qt.callLater(win.editStudySheet, sh)
                    }
                }
                InfoPage {
                    id: infoPage
                    anchors.fill: parent
                    visible: nav.page === "trackinfo"
                    playing: !!player.current && !!infoPage.info && player.current.id === infoPage.info.id
                    onPlay: (t) => { if (!infoPage.playing) player.playList([t], 0) }
                    knownArtists: artistGrid.artists.map(function (a) { return a.name.toLowerCase() })
                    onOpenLyrics: (t) => win.showLyricsOf(t)
                    onOpenAlbum: (t) => nav.openAlbumById(t.albumId)
                    onOpenArtistByName: (name) => win.openArtistNamed(name)
                    onStarToggled: (t, s) => win.onStar(t, s)
                    onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
                    onShowInFolder: (t) => { if (!library.showInFolder(t.id)) toast.show("Não foi possível abrir a pasta") }
                    onEditRequested: (t) => win.editTrack(t)
                    onRefreshOnline: (t) => { infoPage.loading = true; library.requestOnlineInfo("track", t.id, true) }
                    onOpenLink: (url) => Qt.openUrlExternally(url)
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
                    bigTitle: nav.page === "group" && nav.group ? nav.group.name : nav.page === "added" ? "Recém-adicionadas" : ""
                    kicker: nav.page === "group" && nav.group ? nav.group.label : nav.page === "added" ? "Coleção" : ""
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
                    emptyIcon: nav.page === "starred" ? "unstar" : nav.page === "recent" ? "recent" : nav.page === "mostplayed" ? "plays" : "playlist"
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

                RecapPage {
                    id: recapPage
                    anchors.fill: parent
                    visible: nav.page === "recap"
                    onVisibleChanged: if (visible) reload()
                    tracking: win.trackListening
                    onPlayTrack: (id) => {
                        var t = JSON.parse(library.tracksByIdsJson(JSON.stringify([id])))
                        if (t.length) player.playList(t, 0); else toast.show("Essa música não está mais na biblioteca")
                    }
                    onPlayTop: (ids) => {
                        var t = JSON.parse(library.tracksByIdsJson(JSON.stringify(ids)))
                        if (t.length) player.playList(t, 0); else toast.show("Essas músicas não estão mais na biblioteca")
                    }
                    onOpenArtist: (id) => nav.openArtistById(id)
                    onOpenAlbum: (id) => nav.openAlbumById(id)
                    onTurnOn: win.setPref("listening", true)
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
                    onGoArtist: (t) => win.goToArtistOf(t)
                    onGoAlbum: (t) => win.goToAlbumOf(t)
                    onEditLyrics: lyricsEditor.openWith(player.current, win.lyrics)
                    onStarToggled: (t, s) => win.onStar(t, s)
                    excerpt: win.excerpt
                    hasSheet: win.currentHasSheet
                    onStudy: { if (player.current) win.studyTrack(player.current) }
                    excerptPlaying: excerptPlay.active
                    onExcerptSet: (t, s, e) => win.setExcerpt(t, s, e)
                    onExcerptCleared: (t) => win.setExcerpt(t, -1, -1)
                    onPlayExcerpt: excerptPlay.toggle()
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
            excerpt: win.excerpt
            hasSheet: win.currentHasSheet
            onStudy: { if (player.current) win.studyTrack(player.current) }
            excerptPlaying: excerptPlay.active
            onPlayExcerpt: excerptPlay.toggle()
            onMenuRequested: (t, x, y) => win.onTrackMenu(t, x, y)
            onGoArtist: (t) => win.goToArtistOf(t)
            onGoAlbum: (t) => win.goToAlbumOf(t)
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
            onToggle: player.togglePlay()
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
        saveBeside: win.prefs.lrcbeside
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
        onStudy: (t) => win.studyTrack(t)
        onToggleExplicit: (t, shown) => {
            var e = library.setExplicit(t.id, shown ? 0 : 1)
            Prefs.setExplicit(t.id, e)
            toast.show(shown ? "Selo E removido" : "Marcada como explícita")
        }
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
        onGoToArtist: (t) => win.goToArtistOf(t)
        onToggleStar: (t) => { win.onStar(t, !t.starred); toast.show(t.starred ? "Adicionada às favoritas" : "Tirada das favoritas") }
        onShare: (t) => win.copyText(t.title + " — " + t.artist + (t.album ? " (" + t.album + ")" : ""), "Título e artista copiados")
        onStartStation: (t) => win.startStation(t)
        onShowInfo: (t) => nav.openTrackInfo(t)
        onEditInfo: (t) => win.editTrack(t)
        onShowLyrics: (t) => win.showLyricsOf(t)
        onCopyLyrics: (t) => {
            var txt = library.lyricsText(t.id)
            if (txt) win.copyText(t.title + " — " + t.artist + "\n\n" + txt, "Letra copiada")
            else toast.show("A letra desta música ainda não foi baixada")
        }
        onEditLyrics: (t) => {
            var cur = player.current && player.current.id === t.id
            var txt = library.lyricsText(t.id)
            lyricsEditor.openWith(t, cur ? win.lyrics : txt ? { kind: "plain", text: txt } : { kind: "none" })
        }
        onShowInFolder: (t) => { if (!library.showInFolder(t.id)) toast.show("Não foi possível abrir a pasta") }
    }
    TextPrompt { id: prompt }

    // ---------- editing a song ----------
    function editTrack(t) {
        var f = JSON.parse(library.editableJson(t.id))
        if (!f) { toast.show("Esta música não está na biblioteca"); return }
        trackEdit.start(t, f, win.prefs.edittags)
    }
    TrackEditDialog {
        id: trackEdit
        onPickCover: library.pickPath("trackcover", "Escolha a imagem da capa", false)
        onSubmit: (id, json, cover, writeFile) => {
            if (orig.local) win.setPref("edittags", writeFile)
            library.saveTrackEdit(id, json, cover, writeFile)
        }
        onRevert: (id) => {
            if (library.revertTrackEdit(id)) toast.show(trackEdit.orig && trackEdit.orig.local ? "Lendo de novo as informações do arquivo…" : "Mudanças desfeitas; voltam do servidor na próxima sincronização")
        }
    }
    FileDialog {
        id: coverFileDialog
        title: "Escolha a imagem da capa"
        nameFilters: ["Imagens (*.jpg *.jpeg *.png *.webp)", "Todos os arquivos (*)"]
        onAccepted: trackEdit.coverPicked(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
    }
    Connections {
        target: library
        function onTrackEdited(trackId, json) {
            var res = JSON.parse(json); trackId = Number(trackId)
            trackEdit.finished(res)
            if (res.error) return
            toast.show(res.wroteFile ? "Informações salvas no arquivo"
                : res.warning ? "Salvo só no Arara Music: " + res.warning
                : "Informações salvas")
            var fresh = res.track
            if (!fresh) return
            // Songs already in the queue show the new details right away.
            var q = player.queue, changed = false
            for (var i = 0; i < q.length; i++) {
                if (q[i] && q[i].id === trackId && !q[i].free) {
                    if (!changed) { q = q.slice(); changed = true }
                    q[i] = Object.assign({}, q[i], fresh)
                }
            }
            if (changed) { player.queue = q; player.save() }
            if (nav.page === "trackinfo" && infoPage.info && infoPage.info.id === trackId) { nav.trackInfo = fresh; win.loadTrackInfo(fresh) }
            if (nav.page === "album" && nav.album) {
                var a = albumGrid.albums.find(function (x) { return x.id === nav.album.id })
                if (!a && fresh.albumId !== null && fresh.albumId !== undefined) a = albumGrid.albums.find(function (x) { return x.id === fresh.albumId })
                if (a) { nav.album = a; albumPage.tracks = JSON.parse(library.albumTracksJson(a.id)) }
            }
            if (player.current && player.current.id === trackId) win.refreshCoverLook()
        }
    }
    // Plays the favourite excerpt of the current song: jumps to its start and
    // pauses (with the usual short fade) at its end. Changing song, or seeking
    // away from the excerpt, ends it.
    QtObject {
        id: excerptPlay
        property bool active: false
        property int trackId: -1
        property real end: 0
        property real start: 0
        property real last: 0
        property double since: 0
        function toggle() {
            if (active) { stop(true); return }
            var x = win.excerpt
            if (!x || !player.current) return
            trackId = player.current.id; start = x.s; end = x.e; last = x.s; since = Date.now()
            active = true
            player.seekTo(x.s)
            if (media.playbackState !== MediaPlayer.PlayingState) player.resume()
        }
        function stop(pause) {
            if (!active) return
            active = false
            if (pause && media.playbackState === MediaPlayer.PlayingState) player.pause()
        }
        function check(pos) {
            if (!active) return
            if (!player.current || player.current.id !== trackId) { active = false; return }
            // Right after the jump the backend may still report the old position.
            if (Date.now() - since < 800) { if (pos >= start - 200 && pos < end) last = pos; return }
            // A jump by hand (not the playback moving on) cancels it.
            if (pos < start - 1500 || pos - last > 2500) { active = false; return }
            last = pos
            if (pos >= end - 150) stop(true)
        }
    }
    Connections {
        target: media
        function onPositionChanged() { excerptPlay.check(media.position) }
    }

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
            "Espaço: tocar ou pausar\nCtrl+,: preferências\nCtrl+→ / Ctrl+←: próxima / anterior\nCtrl+F: buscar\nCtrl+L: letra em tela cheia\n[ / ]: mais devagar / mais rápido\n\\: velocidade normal\nEsc: voltar\nCtrl+Q: sair\n\nNo editor de letras: Enter marca o verso, Backspace desfaz, ← volta 5 s")
        onAbout: prompt.info("Arara Music 0.7.35",
            "Player de música leve em Rust e Qt, com temas GNOME, Apple, Android e Windows.\nLetras do LRCLIB, servidores Navidrome e Jellyfin.\n\nLicença GPL-3.0 · ícones do tema Adwaita")
    }
    // Decodes the animated covers once for every place that shows them.
    MotionHub {
        id: motionHub
        Component.onCompleted: Prefs.motionHub = motionHub
    }

    PreferencesDialog {
        id: prefsDialog
        parent: frame
        anchors.fill: parent
        prefs: win.prefs
        setFn: win.setPref
        onChooseFolders: { foldersDialog.dirs = JSON.parse(library.libraryDirsJson()); foldersDialog.open() }
        onRescan: { library.changeLibraryDir(library.libraryDir); toast.show("Reindexando a biblioteca…") }
        onRebuildCovers: { library.rebuildCovers(); toast.show("Refazendo as capas dos álbuns…") }
        onOpenAlbum: (id) => { prefsDialog.close(); win.lyricsMode = false; nav.openAlbumById(id) }
        onResetAll: prompt.confirm("Restaurar as preferências?", "Tema, cores, reprodução e letras voltam ao padrão.", "Restaurar", function () { win.resetPrefs() })
        onClearHistory: prompt.confirm("Apagar o histórico de escuta?", "Todas as retrospectivas voltam a zero. Não dá para desfazer.", "Apagar", function () {
            listen.restart(); library.clearListens(); recapPage.reload(); toast.show("Histórico de escuta apagado")
        })
    }
    // Fallback when the portal's file chooser is missing.
    FileDialog {
        id: coverDialog
        property int albumId: -1
        title: "Escolha a imagem da capa"
        nameFilters: ["Imagens (*.jpg *.jpeg *.png *.webp)", "Todos os arquivos (*)"]
        onAccepted: win.useAlbumCover(albumId, decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
    }
    FolderDialog {
        id: folderDialog
        property bool adding: false
        title: adding ? "Adicionar pasta de músicas" : "Escolha a pasta de músicas"
        currentFolder: Qt.platform.os === "windows" ? "file:///" + library.libraryDir.replace(/\\/g, "/") : "file://" + library.libraryDir
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

    onClosing: { listen.flush(); player.save() }

    Shortcut { sequence: "Space"; enabled: !search.activeFocus && !prompt.visible && !trackEdit.visible && !lyricsEditor.visible && !addServer.visible && !importDialog.visible; onActivated: playerBar.toggle() }
    Shortcut { sequence: "Ctrl+F"; onActivated: nav.go("songs") }
    Shortcut { sequence: "Ctrl+Right"; onActivated: player.next() }
    Shortcut { sequence: "Ctrl+Left"; onActivated: player.prev() }
    Shortcut { sequence: "Ctrl+L"; onActivated: win.lyricsMode = !win.lyricsMode }
    // Speed: [ slower, ] faster, \ back to normal (5% steps)
    Shortcut { sequence: "["; enabled: !search.activeFocus; onActivated: win.setRate(Prefs.playbackRate - 0.05) }
    Shortcut { sequence: "]"; enabled: !search.activeFocus; onActivated: win.setRate(Prefs.playbackRate + 0.05) }
    Shortcut { sequence: "\\"; enabled: !search.activeFocus; onActivated: win.setRate(1) }
    Shortcut { sequence: "Escape"; onActivated: { if (prefsDialog.visible) prefsDialog.close(); else if (lyricsEditor.visible) lyricsEditor.visible = false; else if (win.lyricsMode) win.lyricsMode = false; else if (nav.canGoBack) nav.back() } }
    Shortcut { sequences: ["Alt+Left", "Back"]; enabled: nav.canGoBack; onActivated: nav.back() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.close() }
    Shortcut { sequence: "Ctrl+,"; onActivated: prefsDialog.visible ? prefsDialog.close() : prefsDialog.open() }
}
