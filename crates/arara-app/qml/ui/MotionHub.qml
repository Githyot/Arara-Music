import QtQuick
import QtMultimedia
import AraraStyle

// Plays the animated covers for the whole window. Every MotionCover showing
// the same album shares one decoder here (album page, panel and lyrics screen
// at once cost the same as one), and a video is dropped as soon as no cover
// shows it, which frees the decoder and its memory.
//
// While the window is in the background the videos pause on their current
// frame instead of going back to the still cover, so nothing jumps.
Item {
    id: hub
    width: 0; height: 0
    property bool paused: false
    property var refs: ({})

    function acquire(url) {
        if (!url) return null
        refs[url] = (refs[url] || 0) + 1
        var c = clip(url)
        if (c) return c
        clips.append({ url: url })
        return clip(url)
    }
    function release(url) {
        if (!(url in refs)) return
        if (--refs[url] > 0) return
        delete refs[url]
        for (var i = 0; i < clips.count; i++)
            if (clips.get(i).url === url) { clips.remove(i); return }
    }
    function clip(url) {
        for (var i = 0; i < rep.count; i++) {
            var it = rep.itemAt(i)
            if (it && it.url === url) return it
        }
        return null
    }

    ListModel { id: clips }
    Repeater {
        id: rep
        model: clips
        delegate: Item {
            id: c
            required property string url
            property alias video: out
            // Set once the first frame is out and kept through every loop, so
            // the restart never fades back to the still cover.
            property bool shown: false
            property bool broken: false
            MediaPlayer {
                id: player
                source: c.url
                loops: MediaPlayer.Infinite
                videoOutput: out
                onPositionChanged: if (player.position > 0 && !c.shown) c.shown = true
                onErrorOccurred: (error, message) => { console.warn("motion cover:", message); c.broken = true }
                Component.onCompleted: if (!hub.paused) play()
            }
            Connections {
                target: hub
                function onPausedChanged() { if (hub.paused) player.pause(); else player.play() }
            }
            VideoOutput {
                id: out
                // The covers sample this texture; 640 px is the largest cover we draw.
                width: 640; height: 640
                fillMode: VideoOutput.PreserveAspectCrop
                visible: false
            }
        }
    }
}
