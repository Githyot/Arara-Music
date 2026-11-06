import QtQuick
import AraraStyle

// Karaoke screen: the content area turns into a blurred-cover backdrop with
// a gradient of the cover's colours, the cover and controls on the left and
// big synced lyrics on the right. The sidebar and header stay visible.
Item {
    id: ls
    property var track: null
    property var lyrics: ({ kind: "none" })
    property bool loadingLyrics: false
    property bool playing: false
    property real position: 0
    property real duration: 0
    property bool shuffle: false
    property string repeat: "off"
    property real volume: 1.0
    property string backdrop: ""
    property var colors: []
    signal toggle()
    signal next()
    signal prev()
    signal seek(real ms)
    signal toggleShuffle()
    signal cycleRepeat()
    signal volumeMoved(real v)
    signal close()
    signal editLyrics()
    signal refetchLyrics()
    signal starToggled(var track, bool starred)
    signal addToPlaylist(var track, real x, real y)

    readonly property bool wide: width > 760
    // On very wide windows keep cover + lyrics together in the middle.
    readonly property real stage: Math.min(width, 1400)
    readonly property real pad: wide ? (width - stage) / 2 : 0
    clip: true

    // ---- backdrop: gradient of the cover's colours + the blurred cover on top ----
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: ls.colors[0] || "#2b3a55" }
            GradientStop { position: 0.55; color: ls.colors[1] || "#1f3b4d" }
            GradientStop { position: 1; color: ls.colors[3] || "#222226" }
        }
    }
    Image {
        anchors.fill: parent
        source: ls.backdrop
        fillMode: Image.PreserveAspectCrop
        smooth: true; asynchronous: true; cache: false
        opacity: 0.55
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.15) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.45) }
        }
    }

    // ---- left: cover, title, controls ----
    Item {
        id: left
        x: ls.pad
        width: ls.wide ? Math.min(500, ls.stage * 0.42) : parent.width
        height: ls.wide ? parent.height : Math.min(parent.height * 0.55, 470)
        Column {
            id: leftCol
            anchors.centerIn: parent
            width: Math.min(left.width - 64, 380)
            spacing: 14
            CoverArt {
                visible: ls.wide || left.height > 380
                width: Math.min(parent.width, ls.wide ? ls.height - 330 : left.height - 230); height: width
                anchors.horizontalCenter: parent.horizontalCenter
                decode: 640
                source: ls.track ? ls.track.coverBig : ""
            }
            Column {
                width: parent.width; spacing: 2
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: ls.track ? ls.track.title : ""
                    color: "white"; font.family: Theme.font; font.pointSize: Theme.headingSize + 1; font.weight: Theme.headingWeight
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: ls.track ? [ls.track.artist, ls.track.album].filter(function (x) { return !!x }).join(" — ") : ""
                    color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pointSize: Theme.fontSize + 1
                }
            }
            PlayerControls {
                width: parent.width
                onDark: true
                playing: ls.playing; position: ls.position; duration: ls.duration
                shuffle: ls.shuffle; repeat: ls.repeat; volume: ls.volume
                onToggle: ls.toggle()
                onNext: ls.next()
                onPrev: ls.prev()
                onSeek: (ms) => ls.seek(ms)
                onToggleShuffle: ls.toggleShuffle()
                onCycleRepeat: ls.cycleRepeat()
                onVolumeMoved: (v) => ls.volumeMoved(v)
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                visible: ls.track !== null
                FlatButton {
                    icon: ls.track && ls.track.starred ? "star" : "unstar"; circular: true; iconColor: "white"
                    color: hovered ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)
                    onClicked: { var s = !ls.track.starred; ls.track.starred = s; ls.starToggled(ls.track, s); ls.trackChanged() }
                }
                FlatButton {
                    id: plBtn
                    icon: "playlist"; circular: true; iconColor: "white"
                    color: hovered ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)
                    onClicked: { var p = plBtn.mapToItem(null, 0, plBtn.height); ls.addToPlaylist(ls.track, p.x, p.y) }
                }
            }
        }
    }

    // ---- right: lyrics ----
    LyricsView {
        x: ls.wide ? ls.pad + left.width : 0
        y: ls.wide ? 0 : left.height
        width: ls.wide ? ls.stage - left.width - 24 : parent.width
        height: ls.wide ? parent.height : parent.height - left.height
        onDark: true
        baseActive: ls.wide ? 30 : 22
        baseLine: ls.wide ? 24 : 18
        lyrics: ls.lyrics
        duration: ls.duration
        loading: ls.loadingLyrics
        position: ls.position
        onSeek: (ms) => ls.seek(ms)
        onAddLyrics: ls.editLyrics()
    }

    Row {
        anchors { right: parent.right; top: parent.top; margins: 12 }
        spacing: 6
        FlatButton { icon: "refresh"; circular: true; iconColor: "white"; visible: ls.track !== null && !ls.loadingLyrics; onClicked: ls.refetchLyrics() }
        FlatButton { icon: "edit"; circular: true; iconColor: "white"; visible: ls.track !== null; onClicked: ls.editLyrics() }
        FlatButton { icon: "close"; circular: true; iconColor: "white"; onClicked: ls.close() }
    }
}
