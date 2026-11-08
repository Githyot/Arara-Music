import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import AraraStyle
import QtQuick.Controls.Basic as QQC

// Right-hand player panel: big cover, title/artist/album, seek with
// elapsed/remaining, transport, wide volume; the queue opens from its button.
Rectangle {
    id: panel
    property var track: null
    property bool playing: false
    property real position: 0
    property real duration: 0
    property bool shuffle: false
    property string repeat: "off"
    property real volume: 1.0
    property var queue: []
    property int queueIndex: -1
    property bool autoplay: false
    property string backdrop: ""
    property string tab: "player"
    property var lyrics: ({ kind: "none" })
    property bool loadingLyrics: false
    signal toggle()
    signal next()
    signal prev()
    signal seek(real ms)
    signal toggleShuffle()
    signal cycleRepeat()
    signal volumeMoved(real v)
    signal jump(int index)
    signal removeAt(int index)
    signal moveItem(int from, int to)
    signal autoplayToggled(bool on)
    signal openLyrics()
    signal close()
    signal starToggled(var track, bool starred)
    // Favourite excerpt (marked on the lyrics screen): a button plays it.
    property var excerpt: null
    property bool excerptPlaying: false
    property var loopRange: null
    signal stopLoop()
    signal playExcerpt()
    signal menuRequested(var track, real x, real y)
    signal goArtist(var track)
    signal goAlbum(var track)

    property var colors: []
    color: "#26272b"
    clip: true

    // Apple-Music-like backdrop: a gradient of the cover's colours, the blurred
    // cover over it, and a soft dark veil so white text always reads.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: panel.colors[0] || "#3a4a66" }
            GradientStop { position: 0.6; color: panel.colors[1] || "#2a3445" }
            GradientStop { position: 1; color: panel.colors[3] || "#24262b" }
        }
    }
    Image {
        anchors.fill: parent
        source: panel.backdrop
        fillMode: Image.PreserveAspectCrop
        smooth: true; asynchronous: true; cache: false
        opacity: 0.6
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.12) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.42) }
        }
    }

    // Top bar: hide-panel on the left, the window's close button on the right (GNOME CSD).
    property bool windowControls: false
    signal closeWindow()
    Item {
        id: closeBtn
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 46
        WindowControls {
            visible: panel.windowControls
            anchors { right: parent.right; rightMargin: Theme.fluent ? 0 : 6; top: Theme.fluent ? parent.top : undefined; verticalCenter: Theme.fluent ? undefined : parent.verticalCenter }
            onDark: true
            all: panel.allWindowButtons
            window: panel.window
        }
    }
    property bool allWindowButtons: false
    property var window: null

    // ---------- Player tab ----------
    Flickable {
        QQC.ScrollBar.vertical: OverlayScrollBar { onDark: true }
        id: playerTab
        visible: opacity > 0
        opacity: panel.tab === "player" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.ms(200) } }
        anchors { left: parent.left; right: parent.right; top: closeBtn.bottom; bottom: parent.bottom }
        contentHeight: Math.max(height, col.height + 24)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            // side margins live here (not on the Flickable) so its clip doesn't cut the cover shadow
            x: 20; width: parent.width - 40
            spacing: 14
            // Cover: full size while playing, shrinks back a little when paused,
            // with a springy zoom between the two (like Apple Music).
            Item {
                // leave the lower part of the panel to the lyrics
                width: Math.min(parent.width, Prefs.lyricsInPanel ? Math.max(140, (playerTab.height - 330) * 0.6) : playerTab.height - 300); height: width
                anchors.horizontalCenter: parent.horizontalCenter
                Item {
                    id: zoom
                    anchors.fill: parent
                    scale: panel.playing ? 1 : 0.8
                    Behavior on scale { NumberAnimation { duration: Theme.ms(520); easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                    // soft, blurred drop shadow below the cover (Apple Music look),
                    // a bit deeper while playing
                    ShaderEffect {
                        readonly property real blur: Math.max(10, parent.width * 0.09)
                        property real margin: blur * 2
                        property size size: Qt.size(width, height)
                        property real radius: parent.width * Theme.coverRound
                        property real offsetY: parent.width * 0.035
                        property real strength: panel.playing ? 0.34 : 0.2
                        Behavior on strength { NumberAnimation { duration: 400 } }
                        x: -margin; y: -margin
                        width: parent.width + margin * 2; height: parent.height + margin * 2
                        fragmentShader: "qrc:/qt/qml/AraraStyle/shadow.frag.qsb"
                    }
                    MotionCover {
                        anchors.fill: parent
                        decode: 640
                        source: panel.track ? panel.track.coverBig : ""
                        albumId: panel.track && panel.track.albumId ? panel.track.albumId : -1
                    }
                }
            }
            Column {
                width: parent.width; spacing: 4
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Text {
                        id: panelTitle
                        width: Math.min(implicitWidth, panel.width - 48 - (panelE.visible ? panelE.width + 8 : 0))
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        text: panel.track ? panel.track.title : "Nada tocando"
                        color: "white"; font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 1; font.weight: Theme.headingWeight
                    }
                    ExplicitBadge {
                        id: panelE
                        anchors.verticalCenter: panelTitle.verticalCenter
                        track: panel.track
                        size: 17
                        fill: Qt.rgba(1, 1, 1, 0.75)
                        ink: "#2b2b2b"
                    }
                }
                // Artist and album are links: the artist opens the artist page, the album the album page.
                Text {
                    id: artistText
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    visible: text !== ""
                    text: panel.track ? panel.track.artist || "" : ""
                    color: "white"; opacity: artistMa.containsMouse ? 1 : 0.85; font.family: Theme.font; font.pointSize: Theme.fontSize + 1
                    font.underline: artistMa.containsMouse
                    MouseArea {
                        id: artistMa
                        anchors.centerIn: parent; width: Math.min(parent.width, parent.contentWidth + 8); height: parent.height
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: panel.goArtist(panel.track)
                    }
                }
                Text {
                    id: albumText
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    visible: text !== ""
                    text: panel.track ? panel.track.album || "" : ""
                    color: Qt.rgba(1, 1, 1, albumMa.containsMouse ? 0.9 : 0.6); font.family: Theme.font; font.pointSize: Theme.fontSize
                    font.underline: albumMa.containsMouse
                    MouseArea {
                        id: albumMa
                        anchors.centerIn: parent; width: Math.min(parent.width, parent.contentWidth + 8); height: parent.height
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: panel.goAlbum(panel.track)
                    }
                }
                // Quality badge (Hi-Res / Sem perdas) + format detail
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    visible: !!(panel.track && panel.track.qualityDetail)
                    Rectangle {
                        visible: !!(panel.track && panel.track.quality)
                        anchors.verticalCenter: parent.verticalCenter
                        width: qb.implicitWidth + 12; height: 18; radius: 9
                        color: "transparent"; border.color: "white"; border.width: 1
                        Text { id: qb; anchors.centerIn: parent; text: panel.track && panel.track.quality ? panel.track.quality : ""; color: "white"; font.family: Theme.font; font.pointSize: Theme.fontSize - 3; font.weight: Font.Bold }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: panel.track && panel.track.qualityDetail ? panel.track.qualityDetail : ""; color: Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
                }
            }
            PlayerControls {
                width: parent.width
                onDark: true
                playing: panel.playing; position: panel.position; duration: panel.duration
                shuffle: panel.shuffle; repeat: panel.repeat; volume: panel.volume
                onToggle: panel.toggle()
                onNext: panel.next()
                onPrev: panel.prev()
                onSeek: (ms) => panel.seek(ms)
                onToggleShuffle: panel.toggleShuffle()
                onCycleRepeat: panel.cycleRepeat()
                onVolumeMoved: (v) => panel.volumeMoved(v)
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                visible: panel.track !== null
                FlatButton {
                    icon: panel.track && panel.track.starred ? "star" : "unstar"; circular: true; iconColor: "white"
                    onClicked: { var s = !panel.track.starred; panel.track.starred = s; panel.starToggled(panel.track, s); panel.trackChanged() }
                }
                FlatButton {
                    visible: panel.excerpt !== null
                    icon: panel.excerptPlaying ? "pause" : "excerpt"; circular: true; iconColor: "white"
                    tip: panel.excerptPlaying ? "Parar o trecho preferido" : "Tocar o trecho preferido"
                    color: panel.excerptPlaying ? Qt.rgba(1, 1, 1, hovered ? 0.4 : 0.3) : hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
                    onClicked: panel.playExcerpt()
                }
                FlatButton { icon: "lyrics"; circular: true; iconColor: "white"; tip: "Letra"; onClicked: panel.openLyrics() }
                FlatButton { icon: "queue"; circular: true; iconColor: "white"; tip: "Fila"; onClicked: panel.tab = "queue" }
                FlatButton {
                    id: more; icon: "more"; circular: true; iconColor: "white"
                    onClicked: { var p = more.mapToItem(null, 0, more.height); panel.menuRequested(panel.track, p.x, p.y) }
                }
            }
            // A/B loop running: shows the part, click to stop.
            Rectangle {
                visible: panel.loopRange !== null && panel.track !== null
                anchors.horizontalCenter: parent.horizontalCenter
                width: pLoopRow.implicitWidth + 20; height: 32; radius: 16
                color: pLoopMa.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.14)
                Row {
                    id: pLoopRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "repeat"; size: 14; color: "white" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.loopRange ? "Em loop: " + fmtMs(panel.loopRange.s) + " – " + fmtMs(panel.loopRange.e) + "  ·  Parar" : ""
                        color: "white"; font.family: Theme.font; font.pointSize: Theme.fontSize - 1; font.weight: Font.DemiBold
                        function fmtMs(ms) { var t = Math.max(0, Math.round(ms / 1000)); return Math.floor(t / 60) + ":" + ("0" + (t % 60)).slice(-2) }
                    }
                }
                MouseArea { id: pLoopMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: panel.stopLoop() }
            }
            // Lyrics under the controls; click to open the full lyrics screen.
            Item {
                id: mini
                width: parent.width
                height: Math.max(120, playerTab.height - y - 8)
                visible: panel.track !== null && Prefs.lyricsInPanel
                LyricsView {
                    anchors.fill: parent
                    onDark: true
                    baseActive: 16; baseLine: 13
                    lyrics: panel.lyrics
                    loading: panel.loadingLyrics
                    position: panel.position
                    playing: panel.playing
                    duration: panel.duration
                    showAddButton: false
                    compact: true
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: panel.openLyrics()
                    Rectangle {
                        anchors.fill: parent; radius: Theme.cardRadius
                        color: "white"; opacity: parent.containsMouse ? 0.06 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    Rectangle {
                        anchors { right: parent.right; top: parent.top; margins: 6 }
                        visible: parent.containsMouse
                        width: hint.implicitWidth + 16; height: 22; radius: 11
                        color: Qt.rgba(0, 0, 0, 0.35)
                        Text { id: hint; anchors.centerIn: parent; text: "Ampliar letra"; color: "white"; font.family: Theme.font; font.pointSize: Theme.fontSize - 3 }
                    }
                }
            }
        }
    }

    // ---------- Queue tab ----------
    Item {
        visible: opacity > 0
        opacity: panel.tab === "queue" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.ms(200) } }
        anchors { left: parent.left; right: parent.right; top: closeBtn.bottom; bottom: parent.bottom }
        // Header: back to the player, title and size of the queue.
        Item {
            id: queueHead
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 16 }
            height: 40
            FlatButton {
                id: queueBack
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                icon: "back"; circular: true; iconColor: "white"; tip: "Voltar ao player"
                onClicked: panel.tab = "player"
            }
            Text {
                anchors { left: queueBack.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                text: "Fila"; color: "white"
                font.family: Theme.displayFont; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: panel.queue.length + (panel.queue.length === 1 ? " música" : " músicas")
                color: Qt.rgba(1, 1, 1, 0.65); font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
        }
        // AdwSwitchRow-like autoplay toggle
        Item {
            id: autoRow
            anchors { left: parent.left; right: parent.right; top: queueHead.bottom; leftMargin: 20; rightMargin: 16 }
            height: 56
            Column {
                anchors { left: parent.left; right: sw.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                Text { text: "Reprodução automática"; color: "white"; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                Text { width: parent.width; wrapMode: Text.Wrap; text: "Quando a fila acabar, continua com músicas parecidas"; color: Qt.rgba(1, 1, 1, 0.65); font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
            }
            Toggle {
                id: sw
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                checked: panel.autoplay
                onToggled: panel.autoplayToggled(!panel.autoplay)
            }
        }
        QueueView {
            anchors { left: parent.left; right: parent.right; top: autoRow.bottom; bottom: parent.bottom }
            side: 8
            onDark: true
            queue: panel.queue
            current: panel.queueIndex
            onJump: (i) => panel.jump(i)
            onRemoveAt: (i) => panel.removeAt(i)
            onMoveItem: (f, t) => panel.moveItem(f, t)
        }
    }
}
