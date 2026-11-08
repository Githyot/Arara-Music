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
    signal goArtist(var track)
    signal goAlbum(var track)
    signal editLyrics()
    signal refetchLyrics()
    signal starToggled(var track, bool starred)
    signal addToPlaylist(var track, real x, real y)
    // Favourite excerpt of this song ({ s, e } in ms, or null) and whether it
    // is playing right now.
    property var excerpt: null
    property bool excerptPlaying: false
    // Tem cifra no Arara Cypher: botão Estudar ao lado do trecho preferido.
    property bool hasSheet: false
    signal study()
    signal excerptSet(var track, real s, real e)
    signal excerptCleared(var track)
    signal playExcerpt()

    // Marking a new excerpt: "" (off), "start", then "end". A line of the
    // lyrics, or the current position, gives each point.
    property string marking: ""
    property real pendingS: -1
    property real pendingSEnd: -1
    onTrackChanged: marking = ""
    function startMarking() { pendingS = -1; pendingSEnd = -1; marking = "start" }
    // t: where the picked point starts; e: where its line ends (same as t for
    // the current position).
    function pick(t, e) {
        if (marking === "start") { pendingS = t; pendingSEnd = e; marking = "end"; return }
        if (marking !== "end") return
        var s = pendingS, end = e
        // Picked a line before the start: it becomes the start instead.
        if (t < pendingS) { s = t; end = Math.max(pendingSEnd, e) }
        if (end - s < 1000) end = s + 1000
        marking = ""
        ls.excerptSet(ls.track, Math.round(s), Math.round(end))
    }
    function fmt(ms) {
        var t = Math.max(0, Math.round(ms / 1000))
        return Math.floor(t / 60) + ":" + ("0" + (t % 60)).slice(-2)
    }

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
            MotionCover {
                visible: ls.wide || left.height > 380
                width: Math.min(parent.width, ls.wide ? ls.height - 330 : left.height - 230); height: width
                anchors.horizontalCenter: parent.horizontalCenter
                decode: 640
                source: ls.track ? ls.track.coverBig : ""
                albumId: ls.track && ls.track.albumId ? ls.track.albumId : -1
                active: ls.visible
            }
            Column {
                width: parent.width; spacing: 2
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Text {
                        id: lsTitle
                        width: Math.min(implicitWidth, leftCol.width - (lsE.visible ? lsE.width + 8 : 0))
                        elide: Text.ElideRight
                        text: ls.track ? ls.track.title : ""
                        color: "white"; font.family: Theme.font; font.pointSize: Theme.headingSize + 1; font.weight: Theme.headingWeight
                    }
                    ExplicitBadge { id: lsE; anchors.verticalCenter: lsTitle.verticalCenter; track: ls.track; size: 17; fill: Qt.rgba(1, 1, 1, 0.75); ink: "#2b2b2b" }
                }
                // "Artist — Album": each name is a link to its page, like in the side panel.
                Row {
                    id: links
                    readonly property string artist: ls.track ? ls.track.artist || "" : ""
                    readonly property string album: ls.track ? ls.track.album || "" : ""
                    readonly property real room: leftCol.width - (sep.visible ? sep.implicitWidth : 0)
                    anchors.horizontalCenter: parent.horizontalCenter
                    LinkText {
                        id: artistLink
                        text: links.artist
                        width: Math.min(implicitWidth, links.album ? Math.max(links.room / 2, links.room - albumLink.implicitWidth) : links.room)
                        onActivated: ls.goArtist(ls.track)
                    }
                    Text {
                        id: sep
                        visible: links.artist !== "" && links.album !== ""
                        text: " — "
                        color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pointSize: Theme.fontSize + 1
                    }
                    LinkText {
                        id: albumLink
                        text: links.album
                        width: Math.min(implicitWidth, links.room - artistLink.width)
                        onActivated: ls.goAlbum(ls.track)
                    }
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
                // Plays the favourite excerpt (shown once one is marked).
                FlatButton {
                    visible: ls.excerpt !== null
                    icon: ls.excerptPlaying ? "pause" : "excerpt"; circular: true; iconColor: "white"
                    tip: ls.excerpt ? (ls.excerptPlaying ? "Parar o trecho preferido" : "Tocar o trecho preferido (" + ls.fmt(ls.excerpt.s) + " – " + ls.fmt(ls.excerpt.e) + ")") : ""
                    color: ls.excerptPlaying ? Qt.rgba(1, 1, 1, hovered ? 0.4 : 0.32) : hovered ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)
                    onClicked: ls.playExcerpt()
                }
                FlatButton {
                    visible: ls.hasSheet
                    icon: "study"; circular: true; iconColor: "white"
                    tip: "Estudar: cifra, letra e loop"
                    color: hovered ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)
                    onClicked: ls.study()
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
        playing: ls.playing
        onSeek: (ms) => ls.seek(ms)
        onAddLyrics: ls.editLyrics()
        picking: ls.marking !== ""
        markFrom: ls.marking === "end" ? ls.pendingS : ls.marking === "" && ls.excerpt ? ls.excerpt.s : -1
        markTo: ls.marking === "" && ls.excerpt ? ls.excerpt.e : -1
        onPicked: (t, e) => ls.pick(t, e)
    }

    // Marking bar: what to do next, over the top of the lyrics.
    Rectangle {
        id: markBar
        visible: ls.marking !== ""
        z: 2
        readonly property real areaX: ls.wide ? ls.pad + left.width : 0
        readonly property real areaW: ls.wide ? ls.stage - left.width - 24 : ls.width
        x: areaX + Math.max(12, (areaW - width) / 2)
        y: ls.wide ? 60 : left.height + 8
        width: Math.min(areaW - 24, markCol.implicitWidth + 32)
        height: markCol.implicitHeight + 24
        radius: 14
        color: Qt.rgba(0, 0, 0, 0.55)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        Column {
            id: markCol
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 10
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: "white"; font.family: Theme.font; font.pointSize: Theme.fontSize + 1; font.weight: Font.DemiBold
                text: ls.marking === "start"
                    ? (ls.lyrics.kind === "synced" ? "Toque na linha onde o trecho preferido começa" : "Toque em “Começa aqui” quando o trecho preferido começar")
                    : (ls.lyrics.kind === "synced" ? "Agora toque na linha onde ele termina" : "Agora toque em “Termina aqui” quando ele acabar")
            }
            Text {
                width: parent.width
                visible: ls.marking === "end"
                horizontalAlignment: Text.AlignHCenter
                color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pointSize: Theme.fontSize
                text: "Começa em " + ls.fmt(ls.pendingS)
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                FlatButton {
                    text: (ls.marking === "start" ? "Começa aqui" : "Termina aqui") + " (" + ls.fmt(ls.position) + ")"
                    textColor: "white"
                    color: hovered ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.16)
                    onClicked: ls.pick(ls.position, ls.position)
                }
                FlatButton {
                    visible: ls.excerpt !== null && ls.marking === "start"
                    text: "Remover trecho"; textColor: "white"
                    color: hovered ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                    onClicked: { ls.marking = ""; ls.excerptCleared(ls.track) }
                }
                FlatButton {
                    text: "Cancelar"; textColor: "white"
                    color: hovered ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                    onClicked: ls.marking = ""
                }
            }
        }
    }

    Row {
        anchors { right: parent.right; top: parent.top; margins: 12 }
        spacing: 6
        FlatButton { icon: "refresh"; circular: true; iconColor: "white"; visible: ls.track !== null && !ls.loadingLyrics; onClicked: ls.refetchLyrics() }
        FlatButton {
            icon: "excerpt-mark"; circular: true; iconColor: "white"
            tip: ls.excerpt ? "Marcar o trecho preferido de novo" : "Marcar o trecho preferido"
            visible: ls.track !== null && !ls.track.free
            checked: ls.marking !== ""
            color: checked ? Qt.rgba(1, 1, 1, 0.3) : hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
            onClicked: ls.marking !== "" ? ls.marking = "" : ls.startMarking()
        }
        FlatButton { icon: "edit"; tip: "Editar a letra"; circular: true; iconColor: "white"; visible: ls.track !== null; onClicked: ls.editLyrics() }
        FlatButton { icon: "pan-down"; circular: true; iconColor: "white"; onClicked: ls.close() }
    }

    component LinkText: Text {
        id: lt
        signal activated()
        visible: text !== ""
        elide: Text.ElideRight
        color: Qt.rgba(1, 1, 1, ma.containsMouse ? 1 : 0.75)
        font.family: Theme.font; font.pointSize: Theme.fontSize + 1
        font.underline: ma.containsMouse
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: lt.activated()
        }
    }
}
