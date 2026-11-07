import QtQuick
import QtMultimedia
import AraraStyle

// Two players ("decks", like a DJ mixer) so one song can fade into the next.
// `active` is the deck the UI follows (position, duration, state); the other
// one preloads the next song, or plays the tail of the previous one during a
// transition. Volume = user volume × per-track gain × the deck's fade.
Item {
    id: root
    visible: false

    property real volume: 1.0
    readonly property real rate: Prefs.playbackRate
    property var device
    // Gain for a track (ReplayGain or measured loudness); set by Main.
    property var gainFor: function (track) { return 1.0 }
    // "equal" (constant power), "linear", "scurve" or "exp"
    property string curve: "equal"

    property MediaPlayer active: deckA
    readonly property MediaPlayer idle: active === deckA ? deckB : deckA
    readonly property bool transitioning: fader.running
    property MediaPlayer outgoing: null

    signal endOfMedia()
    signal failed(string message)
    signal activeStateChanged()
    signal activeLoaded()
    signal transitionFinished()
    signal rateApplied(real rate)

    // Speed 0.25×–2× on both decks. Set imperatively, not bound: the GStreamer
    // backend (older Qt) drops the speed when a new song loads while the property
    // keeps the old value, so each deck applies it again once its song moves.
    function applyRate() { deckA.applyRate(); deckB.applyRate() }

    // ---------- curves ----------
    // progress p in 0..1 → [outgoing gain, incoming gain]
    function gains(p) {
        p = Math.max(0, Math.min(1, p))
        switch (curve) {
        case "linear": return [1 - p, p]
        case "scurve": { var s = p * p * (3 - 2 * p); return [1 - s, s] }
        // "exp": the old song drops fast, the new one comes in late (like a DJ cut)
        case "exp": return [Math.pow(1 - p, 3), Math.pow(p, 0.5) * p]
        default: return [Math.cos(p * Math.PI / 2), Math.sin(p * Math.PI / 2)]
        }
    }

    // ---------- commands ----------
    function stopAll() {
        fader.stop(); pauseFade.stop()
        deckA.stop(); deckB.stop()
        deckA.fade = 1; deckB.fade = 1
        outgoing = null
    }

    // Hard switch: the active deck plays `track` from `startMs`.
    function load(track, startMs, play) {
        finish()
        idle.stop(); idle.track = null
        var d = active
        d.fade = 1
        d.track = track
        d.seekOnLoad = startMs > 0 ? startMs : -1
        if (d.source.toString() === track.url) d.source = ""   // reload the same song from the top
        d.source = track.url
        if (play) d.play()
    }

    // Get the idle deck ready with the next song (paused, at its start point).
    function preload(track, startMs) {
        if (transitioning) return
        var d = idle
        if (d.track && d.track.id === track.id && d.source.toString() === track.url) {
            if (startMs > 0 && Math.abs(d.seekOnLoad - startMs) > 30) d.seekOnLoad = startMs
            return
        }
        d.stop()
        d.fade = 0
        d.track = track
        d.seekOnLoad = startMs > 0 ? startMs : -1
        d.source = track.url
        // Ask GStreamer to open the stream now; it stays silent (fade 0) until used.
        d.pause()
    }
    function isPreloaded(track) { return !!idle.track && idle.track.id === track.id && idle.mediaStatus !== MediaPlayer.InvalidMedia }

    // Fade from the active deck into `track` over `ms` (0 = gapless switch).
    // `cut` stops the old song at once when the fade ends (trimmed silence).
    function crossfade(track, startMs, ms, cut) {
        finish()
        if (!isPreloaded(track)) preload(track, startMs)
        var from = active, to = idle
        outgoing = from
        to.fade = ms > 0 ? 0 : 1
        active = to
        to.play()
        to.applySeek()
        if (ms <= 0) {
            if (cut) from.stop()
            outgoing = null
            from.fade = 1
            transitionFinished()
            return
        }
        fader.duration = Math.max(50, ms / Math.max(0.25, rate))
        fader.cut = cut
        fader.from = 0; fader.to = 1
        fader.start()
    }

    // End a running transition right away (user action during the fade).
    function finish() {
        if (!fader.running) return
        fader.stop()
        settle()
    }
    function settle() {
        if (outgoing) { outgoing.stop(); outgoing.fade = 1; outgoing.track = null; outgoing.source = "" }
        outgoing = null
        active.fade = 1
        transitionFinished()
    }

    // Pause / resume with a short fade (0 ms = instant).
    function pause(ms) {
        finish()
        if (ms <= 0 || active.playbackState !== MediaPlayer.PlayingState) { active.pause(); return }
        pauseFade.stop()
        pauseFade.target = active; pauseFade.from = active.fade; pauseFade.to = 0
        pauseFade.duration = ms; pauseFade.pausing = true
        pauseFade.start()
    }
    function resume(ms) {
        pauseFade.stop()
        if (ms <= 0) { active.fade = 1; active.play(); return }
        active.fade = 0
        active.play()
        pauseFade.target = active; pauseFade.from = 0; pauseFade.to = 1
        pauseFade.duration = ms; pauseFade.pausing = false
        pauseFade.start()
    }

    NumberAnimation {
        id: fader
        property bool cut: false
        property real p: 0
        target: fader; property: "p"
        easing.type: Easing.Linear
        onPChanged: {
            var g = root.gains(p)
            if (root.outgoing) root.outgoing.fade = g[0]
            root.active.fade = g[1]
        }
        onFinished: root.settle()
    }
    NumberAnimation {
        id: pauseFade
        property bool pausing: false
        property: "fade"
        easing.type: Easing.InOutQuad
        onFinished: if (pausing && target) { target.pause(); target.fade = 1 }
    }

    component Deck: MediaPlayer {
        id: d
        property var track: null
        property real fade: 1
        property real seekOnLoad: -1
        readonly property real gain: root.gainFor(d.track)
        property bool rateDirty: true
        onSourceChanged: rateDirty = true
        // Once the new song is really running (position moves), the pipeline accepts the speed.
        onPositionChanged: if (d.rateDirty && d.position > 0 && d.playbackState === MediaPlayer.PlayingState) { d.rateDirty = false; d.applyRate() }
        function applyRate() {
            var r = Prefs.playbackRate
            if (Math.abs(r - 1) > 0.001 && Math.abs(playbackRate - r) < 0.001) playbackRate = 1
            playbackRate = r
        }
        onPlaybackRateChanged: if (d === root.active) root.rateApplied(playbackRate)
        // Qt 6.10+ (FFmpeg backend) can keep the pitch when the speed changes;
        // older Qt with GStreamer does it on its own (scaletempo).
        Component.onCompleted: {
            if (d.pitchCompensation !== undefined) { d.pitchCompensation = true; Prefs.pitchKept = d.pitchCompensation === true }
            applyRate()
        }
        audioOutput: AudioOutput {
            device: root.device
            volume: Math.max(0, Math.min(1, root.volume * d.gainSmooth * d.fade))
        }
        // Gain changes (loudness measured after the song started) glide instead of jumping.
        property real gainSmooth: gain
        Behavior on gainSmooth { NumberAnimation { duration: 800 } }

        // GStreamer only accepts a seek once the stream is seekable (or playing).
        function applySeek() {
            if (seekOnLoad > 0 && seekable) { position = seekOnLoad; seekOnLoad = -1 }
        }
        onSeekableChanged: applySeek()
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) applySeek()
            if (d === root.active) {
                if (mediaStatus === MediaPlayer.EndOfMedia) root.endOfMedia()
                if (mediaStatus === MediaPlayer.LoadedMedia) root.activeLoaded()
            } else if (mediaStatus === MediaPlayer.EndOfMedia) {
                // the old song ran out during a gapless switch or a fade
                d.stop()
            }
        }
        onPlaybackStateChanged: {
            applySeek()
            if (d === root.active) root.activeStateChanged()
        }
        onErrorOccurred: (error, message) => {
            if (d === root.active) root.failed(message)
            else { d.track = null }   // preload failed: the normal path will retry and report it
        }
    }
    Deck { id: deckA }
    Deck { id: deckB; fade: 0 }
    onActiveChanged: activeStateChanged()
}
