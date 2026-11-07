import QtQuick
import AraraStyle

// Full-window "story" of the recap, Wrapped style: one fact per screen, bars
// at the top, advances by itself; click right/left (or the arrow keys) to
// move, Esc to close.
Item {
    id: story
    property var page: null
    readonly property var d: page ? page.recap : ({})
    property int index: 0
    property bool paused: false
    readonly property var slides: {
        var s = ["intro", "minutes"]
        if ((d.topArtists || []).length) s.push("artist")
        if ((d.topArtists || []).length > 1) s.push("artists")
        if ((d.topTracks || []).length) s.push("song")
        if ((d.topTracks || []).length > 1) s.push("songs")
        if ((d.topGenres || []).length) s.push("genres")
        s.push("when", "summary")
        return s
    }
    // GNOME palette pairs, one per screen.
    readonly property var palettes: [["#1c71d8", "#613583"], ["#e66100", "#a51d2d"], ["#9141ac", "#1a5fb4"], ["#26a269", "#1a5fb4"],
                                     ["#c01c28", "#613583"], ["#e5a50a", "#c64600"], ["#2190a4", "#26a269"], ["#613583", "#241f31"], ["#1a5fb4", "#241f31"]]
    readonly property var pal: palettes[index % palettes.length]
    readonly property string key: slides[Math.min(index, slides.length - 1)]

    parent: page && page.Window.window ? page.Window.window.contentItem : null
    anchors.fill: parent
    z: 200
    visible: false
    focus: visible

    function open() { index = 0; paused = false; visible = true; forceActiveFocus(); timer.restart() }
    function close() { visible = false }
    function next() { if (index + 1 < slides.length) { index++; timer.restart() } else timer.stop() }
    function prev() { if (index > 0) { index--; timer.restart() } }
    onIndexChanged: enter.restart()

    Keys.onEscapePressed: close()
    Keys.onRightPressed: next()
    Keys.onLeftPressed: prev()
    Keys.onSpacePressed: paused = !paused

    Timer { id: timer; interval: 6500; running: story.visible && !story.paused && story.index + 1 < story.slides.length; onTriggered: story.next() }

    Rectangle {
        anchors.fill: parent
        radius: story.parent && story.parent.Window.window && story.parent.Window.window.visibility === Window.Maximized ? 0 : Theme.windowRadius
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: story.pal[0]; Behavior on color { ColorAnimation { duration: 600 } } }
            GradientStop { position: 1; color: story.pal[1]; Behavior on color { ColorAnimation { duration: 600 } } }
        }
        // slow floating blobs for texture
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: story.width * (0.5 + index * 0.15); height: width; radius: width / 2
                color: "white"; opacity: 0.06
                x: story.width * [0.6, -0.2, 0.3][index]; y: story.height * [-0.3, 0.5, 0.8][index]
                SequentialAnimation on x {
                    running: story.visible && !Theme.reduceMotion; loops: Animation.Infinite
                    NumberAnimation { to: story.width * [0.4, 0.0, 0.5][index]; duration: 9000 + index * 2000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: story.width * [0.6, -0.2, 0.3][index]; duration: 9000 + index * 2000; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // progress segments
    Row {
        id: bars
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: 14 }
        spacing: 4
        Repeater {
            model: story.slides.length
            Rectangle {
                required property int index
                width: (bars.width - (story.slides.length - 1) * bars.spacing) / story.slides.length
                height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.3)
                Rectangle {
                    height: parent.height; radius: 2; color: "white"
                    width: index < story.index ? parent.width : index > story.index ? 0 : parent.width * fill.p
                }
            }
        }
    }
    QtObject {
        id: fill
        property real p: 0
    }
    NumberAnimation {
        id: fillAnim
        target: fill; property: "p"; from: 0; to: 1; duration: timer.interval
        running: story.visible
        paused: story.paused
    }
    onVisibleChanged: if (visible) fillAnim.restart()

    // click zones
    MouseArea { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: parent.width * 0.3; onClicked: { story.prev(); fillAnim.restart() } }
    MouseArea { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.width * 0.7; onClicked: { story.next(); fillAnim.restart() } }

    // close / pause
    Row {
        anchors { right: parent.right; top: bars.bottom; rightMargin: 12; topMargin: 8 }
        z: 3
        spacing: 4
        FlatButton { icon: story.paused ? "play" : "pause"; tip: story.paused ? "Continuar" : "Pausar"; iconColor: "white"; onClicked: story.paused = !story.paused }
        FlatButton { icon: "close"; iconColor: "white"; onClicked: story.close() }
    }

    // ---------- the screen ----------
    Item {
        id: stage
        anchors { fill: parent; topMargin: 70; bottomMargin: 40; leftMargin: 32; rightMargin: 32 }
        property real shift: 0
        opacity: 1
        transform: Translate { y: stage.shift }
        Loader {
            id: loader
            anchors.centerIn: parent
            width: Math.min(parent.width, 720)
            sourceComponent: ({ intro: cIntro, minutes: cMinutes, artist: cArtist, artists: cArtists, song: cSong, songs: cSongs,
                                genres: cGenres, when: cWhen, summary: cSummary })[story.key]
        }
    }
    ParallelAnimation {
        id: enter
        NumberAnimation { target: stage; property: "opacity"; from: 0; to: 1; duration: Theme.reduceMotion ? 1 : 450; easing.type: Easing.OutCubic }
        NumberAnimation { target: stage; property: "shift"; from: 40; to: 0; duration: Theme.reduceMotion ? 1 : 550; easing.type: Easing.OutCubic }
    }

    component Big: Text {
        width: parent ? parent.width : 0
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        color: "white"; font.family: Theme.displayFont; font.weight: Font.Black
        font.pointSize: 40
    }
    component Small: Text {
        width: parent ? parent.width : 0
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        color: Qt.rgba(1, 1, 1, 0.85); font.family: Theme.font; font.pointSize: Theme.fontSize + 4
    }
    component ListLine: Item {
        property int rank: 1
        property string cover: ""
        property bool round: false
        property string title: ""
        property string sub: ""
        width: parent ? parent.width : 0; height: 64
        Text { id: lr; width: 40; anchors.verticalCenter: parent.verticalCenter; text: rank; color: "white"; font.family: Theme.displayFont; font.pointSize: 26; font.weight: Font.Black }
        CoverArt { id: lc; anchors { left: lr.right; verticalCenter: parent.verticalCenter } width: 54; height: 54; radius: round ? 27 : 6; source: cover }
        Column {
            anchors { left: lc.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
            Text { width: parent.width; text: title; elide: Text.ElideRight; color: "white"; font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 3; font.weight: Font.Bold }
            Text { width: parent.width; text: sub; elide: Text.ElideRight; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pointSize: Theme.fontSize + 1 }
        }
    }

    Component {
        id: cIntro
        Column {
            spacing: 14
            Small { text: "Arara Music" }
            Big { text: "Sua retrospectiva"; font.pointSize: 52 }
            Big { text: story.page.mode === "all" ? "de todos os tempos" : story.page.range.label; font.pointSize: 30; font.weight: Font.Bold; opacity: 0.9 }
            Item { width: 1; height: 20 }
            Small { text: "Vamos ver o que tocou por aqui."; opacity: 0.8 }
        }
    }
    Component {
        id: cMinutes
        Column {
            spacing: 10
            Small { text: "Você ouviu " + story.page.range.phrase }
            Big { text: story.page.num(story.page.mins(story.d.totalMs)); font.pointSize: 96 }
            Big { text: "minutos de música"; font.pointSize: 28; font.weight: Font.Bold }
            Item { width: 1; height: 16 }
            Small {
                readonly property real h: (story.d.totalMs || 0) / 3600000
                text: h >= 48 ? "Dá " + (h / 24).toFixed(1).replace(".", ",") + " dias sem parar." : h >= 2 ? "Dá " + Math.round(h) + " horas de trilha sonora." : "Um bom começo."
            }
            Small { visible: story.page.deltaText() !== ""; text: story.page.deltaText(); opacity: 0.75 }
        }
    }
    Component {
        id: cArtist
        Column {
            readonly property var a: story.d.topArtists[0]
            spacing: 12
            Small { text: "Seu artista favorito foi" }
            CoverArt { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(260, story.height * 0.35); height: width; radius: width / 2; source: a.coverBig || a.cover }
            Big { text: a.name; font.pointSize: 44 }
            Small { text: story.page.minsText(a.ms) + " juntos · " + story.page.plays(a.plays) }
            Small {
                readonly property real share: a.ms / Math.max(1, story.d.totalMs)
                visible: share >= 0.05
                text: "Isso é " + Math.round(share * 100) + "% de tudo o que você ouviu."
                opacity: 0.75
            }
        }
    }
    Component {
        id: cArtists
        Column {
            spacing: 6
            Big { text: "Seus artistas mais ouvidos"; font.pointSize: 30 }
            Item { width: 1; height: 12 }
            Repeater {
                model: story.d.topArtists.slice(0, 5)
                ListLine {
                    required property var modelData
                    required property int index
                    rank: index + 1; round: true; cover: modelData.cover; title: modelData.name
                    sub: story.page.minsText(modelData.ms)
                }
            }
        }
    }
    Component {
        id: cSong
        Column {
            readonly property var t: story.d.topTracks[0]
            spacing: 12
            Small { text: "A música que mais tocou foi" }
            CoverArt { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(260, story.height * 0.35); height: width; source: t.coverBig || t.cover }
            Big { text: t.name; font.pointSize: 40 }
            Small { text: t.artist; font.weight: Font.DemiBold }
            Small { text: "Você ouviu " + story.page.plays(t.plays) + ", " + story.page.minsText(t.ms) + "."; opacity: 0.8 }
        }
    }
    Component {
        id: cSongs
        Column {
            spacing: 6
            Big { text: "Suas músicas mais tocadas"; font.pointSize: 30 }
            Item { width: 1; height: 12 }
            Repeater {
                model: story.d.topTracks.slice(0, 5)
                ListLine {
                    required property var modelData
                    required property int index
                    rank: index + 1; cover: modelData.cover; title: modelData.name
                    sub: modelData.artist + " · " + story.page.plays(modelData.plays)
                }
            }
        }
    }
    Component {
        id: cGenres
        Column {
            spacing: 14
            Small { text: "Seu gênero do momento" }
            Big { text: story.d.topGenres[0].name; font.pointSize: 56 }
            Item { width: 1; height: 8 }
            Repeater {
                model: story.d.topGenres.slice(1, 5)
                Small {
                    required property var modelData
                    required property int index
                    text: (index + 2) + ". " + modelData.name + " · " + Math.max(1, Math.round(modelData.ms / Math.max(1, story.d.totalMs) * 100)) + "%"
                    font.pointSize: Theme.fontSize + 6
                }
            }
        }
    }
    Component {
        id: cWhen
        Column {
            readonly property var p: story.page.personality()
            readonly property int h: story.page.peakIndex(story.d.hours)
            spacing: 12
            Small { text: "Seu jeito de ouvir" }
            Big { text: p.title; font.pointSize: 46 }
            Small { text: p.text }
            Item { width: 1; height: 16 }
            // hours of the day, white bars
            Item {
                width: parent.width; height: 120
                Row {
                    anchors.fill: parent
                    spacing: 3
                    Repeater {
                        model: 24
                        Item {
                            required property int index
                            readonly property real v: (story.d.hours || [])[index] || 0
                            readonly property real mx: Math.max(1, Math.max.apply(null, story.d.hours || [1]))
                            width: (parent.width - 23 * 3) / 24; height: parent.height
                            Rectangle {
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                                width: parent.width; radius: 3
                                height: Math.max(2, (parent.height - 22) * v / mx)
                                color: "white"; opacity: index === story.page.peakIndex(story.d.hours) ? 1 : 0.45
                            }
                            Text {
                                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                visible: index % 6 === 0
                                text: index + "h"; color: Qt.rgba(1, 1, 1, 0.7); font.family: Theme.font; font.pointSize: Theme.fontSize - 2
                            }
                        }
                    }
                }
            }
            Small { visible: h >= 0; text: "O auge é por volta das " + h + "h." }
        }
    }
    Component {
        id: cSummary
        Column {
            spacing: 18
            Big { text: "Sua retrospectiva " + (story.page.mode === "all" ? "de todos os tempos" : story.page.range.label.toLowerCase().indexOf(" a ") > 0 ? "da semana" : story.page.range.phrase.replace(/^em /, "de ")); font.pointSize: 26 }
            Row {
                width: parent.width
                spacing: 24
                Column {
                    width: (parent.width - 24) / 2
                    spacing: 6
                    Text { text: "Top artistas"; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pointSize: Theme.fontSize + 1; font.weight: Font.Bold }
                    Repeater {
                        model: (story.d.topArtists || []).slice(0, 5)
                        Text { required property var modelData; required property int index; width: parent.width; elide: Text.ElideRight; text: (index + 1) + "  " + modelData.name; color: "white"; font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 1; font.weight: Font.Bold }
                    }
                }
                Column {
                    width: (parent.width - 24) / 2
                    spacing: 6
                    Text { text: "Top músicas"; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pointSize: Theme.fontSize + 1; font.weight: Font.Bold }
                    Repeater {
                        model: (story.d.topTracks || []).slice(0, 5)
                        Text { required property var modelData; required property int index; width: parent.width; elide: Text.ElideRight; text: (index + 1) + "  " + modelData.name; color: "white"; font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 1; font.weight: Font.Bold }
                    }
                }
            }
            Row {
                width: parent.width
                spacing: 24
                Column {
                    width: (parent.width - 24) / 2
                    Text { text: "Minutos ouvidos"; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pointSize: Theme.fontSize + 1; font.weight: Font.Bold }
                    Text { text: story.page.num(story.page.mins(story.d.totalMs)); color: "white"; font.family: Theme.displayFont; font.pointSize: 34; font.weight: Font.Black }
                }
                Column {
                    width: (parent.width - 24) / 2
                    Text { text: "Gênero favorito"; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pointSize: Theme.fontSize + 1; font.weight: Font.Bold }
                    Text { width: parent.width; elide: Text.ElideRight; text: (story.d.topGenres || []).length ? story.d.topGenres[0].name : "—"; color: "white"; font.family: Theme.displayFont; font.pointSize: 34; font.weight: Font.Black }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                z: 5
                FlatButton {
                    text: "Tocar as mais ouvidas"; suggested: true
                    onClicked: { story.close(); story.page.playTop((story.d.topTracks || []).filter(function (t) { return t.id }).map(function (t) { return t.id })) }
                }
                Rectangle {
                    height: 34; width: againT.implicitWidth + 28; radius: Theme.material ? 17 : Theme.radius
                    color: againMa.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.2)
                    Text { id: againT; anchors.centerIn: parent; text: "Ver de novo"; color: "white"; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                    MouseArea { id: againMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { story.index = 0; timer.restart(); fillAnim.restart() } }
                }
            }
        }
    }
}
