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
}
