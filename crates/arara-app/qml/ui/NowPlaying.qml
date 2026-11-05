import QtQuick
import AraraStyle

// Full "now playing" view: cover on the left, karaoke lyrics on the right.
Rectangle {
    id: np
    property var track: null
    property var lyrics: ({ kind: "none" })
    property bool loadingLyrics: false
    property real position: 0
    property var queue: []
    property int queueIndex: -1
    property string tab: "lyrics"
    signal seek(real ms)
    signal close()
    signal jump(int index)
    signal removeAt(int index)
    signal moveItem(int from, int to)

    color: Theme.windowBg
    readonly property bool wide: width > 820

    // Soft blurred-looking backdrop from the cover, low-res so it costs ~nothing.
    Image {
        anchors.fill: parent
        source: np.track ? np.track.cover : ""
        sourceSize: Qt.size(16, 16)
        fillMode: Image.PreserveAspectCrop
        smooth: true
        opacity: Theme.dark ? 0.35 : 0.25
        asynchronous: true; cache: false
    }
    Rectangle { anchors.fill: parent; color: Theme.windowBg; opacity: 0.55 }

    Item {
        id: left
        width: np.wide ? parent.width * 0.42 : parent.width
        height: np.wide ? parent.height : parent.height * 0.42
        Column {
            anchors.centerIn: parent
            spacing: 14
            Rectangle {
                width: Math.min(left.width - 64, left.height - 110, 420); height: width
                anchors.horizontalCenter: parent.horizontalCenter
                radius: Theme.cardRadius; color: Theme.cardBg; clip: true
                Image {
                    anchors.fill: parent
                    source: np.track ? np.track.coverBig : ""
                    sourceSize: Qt.size(420, 420); asynchronous: true; cache: false
                    fillMode: Image.PreserveAspectCrop
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: np.track ? np.track.title : ""; color: Theme.fg; font.family: Theme.font; font.pointSize: 18; font.weight: Font.Bold }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: np.track ? np.track.artist + (np.track.album ? " — " + np.track.album : "") : ""; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize + 1 }
        }
    }

    Item {
        id: right
        x: np.wide ? left.width : 0
        y: np.wide ? 0 : left.height
        width: np.wide ? parent.width - left.width : parent.width
        height: np.wide ? parent.height : parent.height - left.height

        // AdwViewSwitcher-like toggle
        Rectangle {
            id: switcher
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
            width: 220; height: 34; radius: Theme.radius; color: Theme.hover
            Row {
                anchors.fill: parent; anchors.margins: 3
                Repeater {
                    model: [{ k: "lyrics", t: "Letra" }, { k: "queue", t: "Fila" }]
                    Rectangle {
                        required property var modelData
                        width: (switcher.width - 6) / 2; height: switcher.height - 6; radius: Theme.radius - 2
                        color: np.tab === modelData.k ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.15) : "#ffffff") : "transparent"
                        Text { anchors.centerIn: parent; text: modelData.t; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; onClicked: np.tab = modelData.k }
                    }
                }
            }
        }

        LyricsView {
            anchors { left: parent.left; right: parent.right; top: switcher.bottom; bottom: parent.bottom; topMargin: 6 }
            visible: np.tab === "lyrics"
            lyrics: np.lyrics
            loading: np.loadingLyrics
            position: np.position
            onSeek: (ms) => np.seek(ms)
        }
        QueueView {
            anchors { left: parent.left; right: parent.right; top: switcher.bottom; bottom: parent.bottom; topMargin: 6 }
            visible: np.tab === "queue"
            queue: np.queue
            current: np.queueIndex
            onJump: (i) => np.jump(i)
            onRemoveAt: (i) => np.removeAt(i)
            onMoveItem: (f, t) => np.moveItem(f, t)
        }
    }

    FlatButton { anchors { right: parent.right; top: parent.top; margins: 12 } icon: "close"; circular: true; onClicked: np.close() }
}
