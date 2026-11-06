import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import AraraStyle

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
        id: playerTab
        visible: opacity > 0
        opacity: panel.tab === "player" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.ms(200) } }
        anchors { left: parent.left; right: parent.right; top: closeBtn.bottom; bottom: parent.bottom; leftMargin: 20; rightMargin: 20 }
        contentHeight: Math.max(height, col.height + 24)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
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
                    // soft shadow, stronger while playing
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            anchors.fill: parent
                            anchors.margins: -(index + 1) * 3
                            anchors.topMargin: -(index + 1) * 3 + 8
                            radius: parent.width * Theme.coverRound + (index + 1) * 3
                            color: "black"
                            opacity: panel.playing ? 0.07 : 0.035
                            Behavior on opacity { NumberAnimation { duration: 400 } }
                        }
                    }
                    CoverArt {
                        anchors.fill: parent
                        decode: 640
                        source: panel.track ? panel.track.coverBig : ""
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
                // Artist and album: click either to go to the artist's or the album's page.
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
                        onClicked: goMenu.openBelow(artistText)
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
                        onClicked: goMenu.openBelow(albumText)
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
                FlatButton { icon: "lyrics"; circular: true; iconColor: "white"; tip: "Letra"; onClicked: panel.openLyrics() }
                FlatButton { icon: "queue"; circular: true; iconColor: "white"; tip: "Fila"; onClicked: panel.tab = "queue" }
                FlatButton {
                    id: more; icon: "more"; circular: true; iconColor: "white"
                    onClicked: { var p = more.mapToItem(null, 0, more.height); panel.menuRequested(panel.track, p.x, p.y) }
                }
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

    // Small popover: go to the artist or to the album of the current track.
    Popup {
        id: goMenu
        parent: panel.Window.contentItem
        width: 220; padding: 6
        modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        function openBelow(item) {
            var p = item.mapToItem(null, item.width / 2, item.height)
            x = Math.max(8, Math.min(p.x - width / 2, (parent ? parent.width : 9999) - width - 8)); y = p.y + 4
            open()
        }
        background: Rectangle {
            radius: Theme.popupRadius; color: Theme.popupBg; border.color: Theme.border
            Rectangle { z: -1; anchors.fill: parent; anchors.margins: -2; radius: parent.radius + 2; color: "#000000"; opacity: 0.08 }
        }
        contentItem: Column {
            Repeater {
                model: [{ k: "artist", i: "artist", t: "Ver página do artista" }, { k: "album", i: "albums", t: "Ver página do álbum" }]
                Rectangle {
                    required property var modelData
                    width: goMenu.width - 12; height: 36; radius: Theme.material ? 0 : Theme.radius
                    color: gm.containsMouse ? Theme.hover : "transparent"
                    Icon { id: gi; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } name: modelData.i; size: 16 }
                    Text { anchors { left: gi.right; leftMargin: 10; verticalCenter: parent.verticalCenter } text: modelData.t; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                    MouseArea {
                        id: gm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { goMenu.close(); if (modelData.k === "artist") panel.goArtist(panel.track); else panel.goAlbum(panel.track) }
                    }
                }
            }
        }
    }
}
