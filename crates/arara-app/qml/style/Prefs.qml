pragma Singleton
import QtQuick

// Runtime preferences that many components read (set by Main from the
// stored settings, changed live from the preferences dialog).
QtObject {
    // Lyrics
    property real lyricsOffset: 0      // ms added to the playback position
    property real lyricsScale: 1.0
    property bool lyricsDuets: true    // put a second singer on the other side
    property bool lyricsInPanel: true
    // Player
    property bool remainingTime: true  // "-1:23" instead of the total length
    // Explicit "E" badge
    property bool showExplicit: true
    property bool explicitLyrics: true // also when only the lyrics look explicit
    // trackId → explicit state changed in this session (menu, lyrics just
    // fetched), so queue/list copies of the track update at once.
    property var explicitOverride: ({})
    function setExplicit(id, kind) {
        var o = Object.assign({}, explicitOverride); o[Number(id)] = kind; explicitOverride = o
    }
    // Playback speed, 0.25–2.0 (1 = normal). Components ask for a change with
    // requestRate(); Main stores it and the binding brings it back here.
    property real playbackRate: 1.0
    readonly property real minRate: 0.25
    readonly property real maxRate: 2.0
    signal requestRate(real rate)
    // Qt 6.10+ keeps the pitch at other speeds; older Qt makes voices higher/lower.
    property bool pitchKept: false
    function clampRate(r) { return Math.max(minRate, Math.min(maxRate, Math.round(r * 100) / 100)) }
    // "1×", "0,75×", "1,5×" (Brazilian decimal comma)
    function rateLabel(r) { return String(Math.round(r * 100) / 100).replace(".", ",") + "×" }
}
