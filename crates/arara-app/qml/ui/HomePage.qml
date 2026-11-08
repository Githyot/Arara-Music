import QtQuick
import AraraStyle

// "Início": the page the app opens on. A big shuffle button, then the albums
// and songs you played lately, what's new in the library, your artists and a
// few albums to rediscover. Everything comes from one query (homeJson), made
// only after the window is on screen, so it costs nothing at startup.
Item {
    id: page
    property var home: ({})
    property int trackCount: 0
    property int albumCount: 0
    property bool scanning: false
    property int playingId: -1
    property int reshuffles: 0
    property date now: new Date()
    signal shuffle(string kind)
    signal openAlbum(var album)
    signal playAlbum(var album)
    signal openArtist(var artist)
    signal play(var tracks, int index)
    signal seeAll(string page)
    signal menuRequested(var track, real x, real y)
    signal starToggled(var track, bool starred)

    function reload() {
        now = new Date()
        var day = Math.floor(now.getTime() / 86400000)
        home = JSON.parse(library.homeJson(day * 31 + reshuffles * 101))
    }

    readonly property var recentAlbums: home.recentAlbums || []
    readonly property var addedAlbums: home.addedAlbums || []
    readonly property var rediscover: home.rediscover || []
    readonly property var topArtists: home.topArtists || []
    readonly property var topTracks: home.topTracks || []
    readonly property var recentTracks: home.recentTracks || []
    readonly property bool noHistory: recentAlbums.length === 0 && topTracks.length === 0
    readonly property bool emptyLibrary: trackCount === 0

    readonly property int side: Math.max(24, (width - 1180) / 2)
    readonly property real cw: width - 2 * side
    readonly property int gap: Theme.compact ? 14 : 18

    readonly property var weekdays: ["domingo", "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado"]
    readonly property var months: ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
    readonly property string greeting: {
        var h = now.getHours()
        return h >= 5 && h < 12 ? "Bom dia" : h >= 12 && h < 18 ? "Boa tarde" : "Boa noite"
    }
    readonly property string dateText: { var d = weekdays[now.getDay()]; return d.charAt(0).toUpperCase() + d.slice(1) + ", " + now.getDate() + " de " + months[now.getMonth()] }
    function num(n) { return Number(n || 0).toLocaleString(Qt.locale("pt_BR"), "f", 0) }
    function time(ms) { var s = Math.round((ms || 0) / 1000); return Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2) }

    // The greeting follows the clock while the page is open.
    Timer { interval: 60000; repeat: true; running: page.visible; onTriggered: page.now = new Date() }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.height + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: page.side; y: 20
            width: page.cw
            spacing: 30

            // ---------- hero: greeting + shuffle ----------
            Rectangle {
                id: hero
                width: parent.width
                height: Math.max(196, heroText.height + 56)
                radius: Theme.cardRadius + 4
                clip: true
                readonly property var lead: page.recentAlbums[0] || page.addedAlbums[0] || null
                readonly property string blur: lead && lead.cover ? library.coverBlur(lead.coverBig || lead.cover) : ""
                readonly property var fan: (page.recentAlbums.length >= 3 ? page.recentAlbums : page.addedAlbums).slice(0, 3)
                readonly property bool showFan: width >= 640 && fan.length >= 3
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.darker(Theme.accent, 1.05) }
                    GradientStop { position: 1; color: Qt.darker(Theme.accent, 2.2) }
                }
                Image {
                    anchors.fill: parent; source: hero.blur; fillMode: Image.PreserveAspectCrop
                    asynchronous: true; cache: false; opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.12) }
                    }
                }

                Column {
                    id: heroText
                    anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                    width: parent.width - 56 - (hero.showFan ? 250 : 0)
                    spacing: 4
                    Text { text: page.dateText; color: Qt.rgba(1, 1, 1, 0.8); font.family: Theme.font; font.pointSize: Theme.fontSize }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: page.greeting
                        color: "white"; font.family: Theme.displayFont; font.pointSize: Theme.titleSize + 12; font.weight: Font.Black
                    }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: page.emptyLibrary ? (page.scanning ? "Indexando sua biblioteca…" : "Sua biblioteca ainda está vazia.")
                            : page.num(page.trackCount) + (page.trackCount === 1 ? " música" : " músicas") + " e " + page.num(page.albumCount) + (page.albumCount === 1 ? " álbum" : " álbuns") + " esperando por você."
                        color: Qt.rgba(1, 1, 1, 0.85); font.family: Theme.font; font.pointSize: Theme.fontSize + 1
                    }
                    Item { width: 1; height: 14 }
                    Flow {
                        width: parent.width
                        spacing: 10
                        visible: !page.emptyLibrary
                        HeroButton { primary: true; icon: "shuffle"; text: "Tocar tudo aleatório"; onClicked: page.shuffle("all") }
                        HeroButton { visible: !!page.home.hasStarred; icon: "star"; text: "Favoritas aleatórias"; onClicked: page.shuffle("starred") }
                    }
                }

                // Three recent covers, fanned out like records on a shelf.
                Item {
                    visible: hero.showFan
                    anchors { right: parent.right; rightMargin: 34; verticalCenter: parent.verticalCenter }
                    width: 220; height: 150
                    Repeater {
                        model: hero.showFan ? hero.fan : []
                        CoverArt {
                            required property var modelData
                            required property int index
                            width: 132; height: 132; decode: 264
                            x: [0, 44, 88][index]; y: [16, 4, 16][index]
                            z: index === 1 ? 2 : 1
                            rotation: [-8, 0, 8][index]
                            source: modelData.coverBig || modelData.cover
                            hovered: fanMa.containsMouse
                            Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; radius: parent.radius + 1; color: Qt.rgba(0, 0, 0, 0.25) }
                            MouseArea { id: fanMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openAlbum(modelData) }
                        }
                    }
                }
            }

            // ---------- empty library ----------
            Column {
                visible: page.emptyLibrary
                width: parent.width
                topPadding: 30
                spacing: 10
                Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "folder-music"; size: 72; color: Theme.dimFg; opacity: 0.7 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 460); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    text: page.scanning ? "As músicas aparecem aqui assim que forem encontradas." : "Escolha a pasta de músicas no menu ☰ › Pastas de músicas."
                    color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
                }
            }

            // ---------- nothing played yet ----------
            Rectangle {
                visible: !page.emptyLibrary && page.noHistory
                width: parent.width; height: hintRow.height + 32
                radius: Theme.cardRadius
                color: Theme.cardBg; border.width: 1; border.color: Theme.border
                Row {
                    id: hintRow
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36
                    spacing: 14
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "recent"; size: 28; color: Theme.accentFg }
                    Column {
                        width: parent.width - 42
                        spacing: 2
                        Text { text: "Seu histórico começa aqui"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize + 1; font.weight: Font.DemiBold }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            text: "Os álbuns e as músicas que você tocar aparecem nesta página, para voltar a eles com um clique."
                            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
                        }
                    }
                }
            }

            Section {
                title: "Ouvidos recentemente"
                visible: page.recentAlbums.length > 0
                more: "recent"
                AlbumRow { albums: page.recentAlbums }
            }
            Section {
                title: "Mais tocadas"
                visible: page.topTracks.length > 0
                more: "mostplayed"
                TrackGrid { tracks: page.topTracks; ranked: true }
            }
            Section {
                title: "Adicionados recentemente"
                visible: page.addedAlbums.length > 0
                more: "added"
                AlbumRow { albums: page.addedAlbums }
            }
            Section {
                title: "Seus artistas"
                visible: page.topArtists.length > 0
                more: "artists"
                ArtistRow { artists: page.topArtists }
            }
            Section {
                title: "Tocadas recentemente"
                visible: page.recentTracks.length > 0
                more: "recent"
                TrackGrid { tracks: page.recentTracks }
            }
            Section {
                title: "Para redescobrir"
                subtitle: "Álbuns que você não ouve há mais de um mês"
                visible: page.rediscover.length > 0
                refreshable: true
                AlbumRow { albums: page.rediscover }
            }
        }
    }

    // ======================================================================
    component HeroButton: Rectangle {
        id: hb
        property bool primary: false
        property string icon: ""
        property string text: ""
        signal clicked()
        height: 40; width: hbRow.width + 36; radius: height / 2
        color: primary ? (hbMa.pressed ? Qt.rgba(1, 1, 1, 0.8) : hbMa.containsMouse ? Qt.rgba(1, 1, 1, 0.94) : "white")
                       : (hbMa.pressed ? Qt.rgba(1, 1, 1, 0.3) : hbMa.containsMouse ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(1, 1, 1, 0.18))
        scale: hbMa.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 100 } }
        Row {
            id: hbRow
            anchors.centerIn: parent
            spacing: 8
            Icon { anchors.verticalCenter: parent.verticalCenter; name: hb.icon; size: 16; color: hb.primary ? "#1d1d20" : "white" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: hb.text; color: hb.primary ? "#1d1d20" : "white"; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.Bold }
        }
        MouseArea { id: hbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: hb.clicked() }
    }

    component Section: Column {
        id: sec
        property string title: ""
        property string subtitle: ""
        property string more: ""
        property bool refreshable: false
        default property alias body: holder.data
        width: col.width
        spacing: 12
        Item {
            width: parent.width; height: Math.max(34, secTitles.height)
            Column {
                id: secTitles
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width - secBtn.width - 12
                spacing: 2
                Text { text: sec.title; color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.headingSize + 1; font.weight: Theme.headingWeight }
                Text { visible: sec.subtitle !== ""; text: sec.subtitle; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
            }
            FlatButton {
                id: secBtn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: sec.more !== "" || sec.refreshable
                text: sec.refreshable ? "" : "Ver tudo"
                icon: sec.refreshable ? "refresh" : ""
                tip: sec.refreshable ? "Outras sugestões" : ""
                onClicked: { if (sec.refreshable) { page.reshuffles++; page.reload() } else page.seeAll(sec.more) }
            }
        }
        Item { id: holder; width: parent.width; height: childrenRect.height }
    }

    // One row of album tiles: as many as fit, never a horizontal scroll.
    component AlbumRow: Row {
        id: ar
        property var albums: []
        readonly property int n: Math.max(2, Math.floor((col.width + page.gap) / (Math.min(Theme.tileMin, 170) + page.gap)))
        readonly property real tile: (col.width - page.gap * (n - 1)) / n
        width: col.width
        spacing: page.gap
        Repeater {
            model: ar.albums.slice(0, ar.n)
            Item {
                id: at
                required property var modelData
                width: ar.tile; height: ar.tile + 50
                CoverArt {
                    id: atArt
                    width: ar.tile; height: ar.tile; decode: Math.round(ar.tile)
                    source: at.modelData.cover
                    hovered: atMa.containsMouse
                    scale: atMa.pressed && !playBtn.hovered ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
                Column {
                    anchors { left: parent.left; right: parent.right; top: atArt.bottom; topMargin: 6 }
                    spacing: 1
                    Text { width: parent.width; text: at.modelData.title; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: at.modelData.artist || ""; elide: Text.ElideRight; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                }
                MouseArea { id: atMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openAlbum(at.modelData) }
                // Play the album without opening it (shows on hover).
                FlatButton {
                    id: playBtn
                    anchors { right: atArt.right; bottom: atArt.bottom; margins: 10 }
                    size: 42; circular: true; suggested: true; icon: "play"; tip: "Tocar o álbum"
                    opacity: atMa.containsMouse || hovered ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: Theme.ms(140) } }
                    onClicked: page.playAlbum(at.modelData)
                }
            }
        }
    }

    component ArtistRow: Row {
        id: rr
        property var artists: []
        readonly property int n: Math.max(3, Math.floor((col.width + page.gap) / (130 + page.gap)))
        readonly property real tile: (col.width - page.gap * (n - 1)) / n
        width: col.width
        spacing: page.gap
        Repeater {
            model: rr.artists.slice(0, rr.n)
            Item {
                id: rt
                required property var modelData
                width: rr.tile; height: rr.tile + 30
                CoverArt {
                    id: rtArt
                    width: rr.tile; height: rr.tile; radius: width / 2; decode: Math.round(rr.tile)
                    source: rt.modelData.cover
                    hovered: rtMa.containsMouse
                    scale: rtMa.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
                Text {
                    anchors { left: parent.left; right: parent.right; top: rtArt.bottom; topMargin: 8 }
                    horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    text: rt.modelData.name; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
                }
                MouseArea { id: rtMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openArtist(rt.modelData) }
            }
        }
    }

    // Songs in two columns (one on narrow windows), five per column.
    component TrackGrid: Grid {
        id: tg
        property var tracks: []
        property bool ranked: false
        readonly property int cols: col.width >= 700 ? 2 : 1
        width: col.width
        columns: cols
        columnSpacing: page.gap
        rowSpacing: 2
        flow: Grid.TopToBottom
        rows: Math.ceil(Math.min(tracks.length, cols * 5) / cols)
        Repeater {
            model: tg.tracks.slice(0, tg.cols * 5)
            Rectangle {
                id: tr
                required property var modelData
                required property int index
                readonly property bool playing: page.playingId === modelData.id
                width: (tg.width - tg.columnSpacing * (tg.cols - 1)) / tg.cols
                height: 58
                radius: Theme.material ? 14 : Theme.radius + 2
                color: trMa.pressed ? Theme.pressed : trMa.containsMouse ? Theme.hover : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    id: rank
                    visible: tg.ranked
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 22; horizontalAlignment: Text.AlignHCenter
                    text: tr.index + 1; color: tr.playing ? Theme.accentFg : Theme.dimFg
                    font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.Bold
                }
                CoverArt {
                    id: trArt
                    anchors { left: tg.ranked ? rank.right : parent.left; leftMargin: tg.ranked ? 6 : 8; verticalCenter: parent.verticalCenter }
                    width: 44; height: 44; decode: 88
                    source: tr.modelData.cover
                }
                Column {
                    anchors { left: trArt.right; leftMargin: 12; right: trRight.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Row {
                        width: parent.width
                        spacing: 6
                        Text {
                            id: trTitle
                            width: Math.min(implicitWidth, parent.width - (trBadge.visible ? trBadge.width + 6 : 0))
                            text: tr.modelData.title; elide: Text.ElideRight
                            color: tr.playing ? Theme.accentFg : Theme.fg
                            font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
                        }
                        ExplicitBadge { id: trBadge; anchors.verticalCenter: parent.verticalCenter; track: tr.modelData; size: 14 }
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: (tr.modelData.artist || "") + (tr.modelData.album ? " · " + tr.modelData.album : "")
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                }
                Row {
                    id: trRight
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: tr.modelData.duration > 0 && tr.width > 360
                        rightPadding: 4
                        text: page.time(tr.modelData.duration); color: Theme.dimFg
                        font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                    FlatButton {
                        id: trMore
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "more"
                        opacity: trMa.containsMouse || hovered ? 1 : 0
                        onClicked: { var p = mapToItem(null, 0, height); page.menuRequested(tr.modelData, p.x, p.y) }
                    }
                }
                MouseArea {
                    id: trMa
                    anchors.fill: parent; z: -1
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => {
                        if (m.button === Qt.RightButton) { var p = mapToItem(null, m.x, m.y); page.menuRequested(tr.modelData, p.x, p.y) }
                        else page.play(tg.tracks, tr.index)
                    }
                }
            }
        }
    }
}
