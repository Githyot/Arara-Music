import QtQuick
import QtMultimedia
import AraraStyle

// Album art that turns into the album's animated cover (a short silent
// looping video, downloaded once into the cache) when the preference is on
// and the album has one. The still cover is always underneath, so nothing
// changes when there's no video or it can't play.
//
// The video player only exists while the cover is on screen, the window isn't
// minimized and `active` is true: when hidden it is destroyed, which frees
// the decoder and its memory instead of keeping a paused one around.
Item {
    id: root
    property string source: ""         // still cover
    property int decode: Math.max(width, height)
    property int albumId: -1
    property bool active: true         // the caller can pause it (e.g. panel hidden)
    // The album page's cover is "primary": while it plays an album, the panel
    // shows that album still, so the same video is never decoded twice.
    property bool primary: false
    property alias hovered: still.hovered
    property string motion: ""         // file:// URL of the cached video
    // Videos that failed to play this session (no H.264 decoder…): stay still.
    property bool broken: false
    readonly property bool playing: loader.item !== null && loader.item.shown

    readonly property var win: Window.window
    // Only while the window is on screen and focused: a player usually sits
    // behind other windows, and then the video costs nothing.
    readonly property bool onScreen: visible && width > 0 && win !== null && win.active
        && win.visibility !== Window.Minimized && win.visibility !== Window.Hidden
    readonly property bool wanted: Prefs.motionCovers && !Theme.reduceMotion && motion !== "" && !broken && active && onScreen
        && (primary || Prefs.motionPrimaryAlbum !== albumId)
    onWantedChanged: claim()
    onAlbumIdChanged: { refresh(); claim() }
    function claim() {
        if (!primary) return
        if (wanted) Prefs.motionPrimaryAlbum = albumId
        else if (Prefs.motionPrimaryAlbum === albumId) Prefs.motionPrimaryAlbum = -1
    }
    Component.onDestruction: if (primary && Prefs.motionPrimaryAlbum === albumId) Prefs.motionPrimaryAlbum = -1

    function refresh() {
        broken = false
        motion = Prefs.motionCovers && albumId >= 0 ? library.motionCover(albumId) : ""
    }
    Component.onCompleted: refresh()
    Connections {
        target: Prefs
        function onMotionCoversChanged() { root.refresh() }
        function onMotionCleared() { root.motion = ""; root.refresh() }
    }
    Connections {
        target: library
        function onMotionCoverReady(id, url) { if (id === root.albumId && url !== "") root.motion = url }
    }

    CoverArt {
        id: still
        anchors.fill: parent
        source: root.source
        decode: root.decode
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: root.wanted
        sourceComponent: Item {
            id: clip
            // Shown once the first frame is out, so the still cover never blinks.
            property bool shown: player.playbackState === MediaPlayer.PlayingState && player.position > 0
            MediaPlayer {
                id: player
                source: root.motion
                loops: MediaPlayer.Infinite
                videoOutput: video
                onErrorOccurred: (error, message) => { console.warn("motion cover:", message); root.broken = true }
                onSourceChanged: play()
                Component.onCompleted: play()
            }
            VideoOutput {
                id: video
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                visible: false
            }
            ShaderEffectSource {
                id: frame
                anchors.fill: parent
                sourceItem: video
                hideSource: true
                live: true
                visible: false
            }
            // Same rounded corners as CoverArt.
            ShaderEffect {
                anchors.fill: parent
                property variant src: frame
                property size size: Qt.size(width, height)
                property real radius: still.radius
                fragmentShader: "qrc:/qt/qml/AraraStyle/rounded.frag.qsb"
                opacity: clip.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            Rectangle { anchors.fill: parent; radius: still.radius; color: "white"; opacity: still.hovered ? 0.08 : 0 }
        }
    }
}
