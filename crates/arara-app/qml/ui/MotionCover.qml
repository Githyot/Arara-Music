import QtQuick
import AraraStyle

// Album art that turns into the album's animated cover (a short silent
// looping video, downloaded once into the cache) when the preference is on
// and the album has one. The still cover is always underneath, so nothing
// changes when there's no video or it can't play.
//
// The video itself is decoded by MotionHub (in Main), shared by every cover
// of the same album and only while one is on screen; this item just draws the
// current frame with rounded corners.
Item {
    id: root
    property string source: ""         // still cover
    property int decode: Math.max(width, height)
    property int albumId: -1
    property bool active: true         // the caller can pause it (e.g. panel hidden)
    property bool primary: false       // kept for callers; sharing makes it unnecessary
    property alias hovered: still.hovered
    property string motion: ""         // file:// URL of the cached video
    // Videos that failed to play this session (no H.264 decoder…): stay still.
    property bool broken: false
    readonly property bool playing: clip !== null && clip.shown

    readonly property var win: Window.window
    readonly property bool onScreen: visible && width > 0 && win !== null
        && win.visibility !== Window.Minimized && win.visibility !== Window.Hidden
    readonly property bool wanted: Prefs.motionCovers && !Theme.reduceMotion && motion !== "" && !broken && active && onScreen
        && Prefs.motionHub !== null

    // The shared clip this cover shows, and the URL it holds in the hub.
    property Item clip: null
    property string held: ""
    function sync() {
        var want = wanted ? motion : ""
        if (want === held) return
        if (held !== "" && Prefs.motionHub) Prefs.motionHub.release(held)
        held = want
        clip = want !== "" ? Prefs.motionHub.acquire(want) : null
    }
    onWantedChanged: sync()
    onMotionChanged: sync()
    readonly property bool clipBroken: clip !== null && clip.broken
    onClipBrokenChanged: if (clipBroken) broken = true
    onAlbumIdChanged: refresh()
    Component.onDestruction: if (held !== "" && Prefs.motionHub) Prefs.motionHub.release(held)

    function refresh() {
        broken = false
        motion = Prefs.motionCovers && albumId >= 0 ? library.motionCover(albumId) : ""
    }
    Component.onCompleted: { refresh(); sync() }
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
        anchors.fill: parent
        active: root.clip !== null
        sourceComponent: Item {
            ShaderEffectSource {
                id: frame
                anchors.fill: parent
                sourceItem: root.clip ? root.clip.video : null
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
                opacity: root.playing ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
            Rectangle { anchors.fill: parent; radius: still.radius; color: "white"; opacity: still.hovered ? 0.08 : 0 }
        }
    }
}
