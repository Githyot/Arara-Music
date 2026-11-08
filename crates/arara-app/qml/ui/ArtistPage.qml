import QtQuick
import AraraStyle
import QtQuick.Controls.Basic as QQC

// Artist page laid out like the album page: photo, name, play buttons and the
// "Sobre o artista" block in a column on the left, the albums on the right
// (on narrow windows: header, albums, then the About block).
Flickable {
    QQC.ScrollBar.vertical: OverlayScrollBar {}
    id: page
    property var artist: null
    property var albums: []
    property int playingId: -1
    property var aboutInfo: null
    property var aboutOnline: null
    property bool aboutLoading: false
    property bool aboutOff: false
    signal playAll(bool shuffle)
    signal openAlbum(var album)
    signal playTracks(var tracks, int index)
    signal openLink(string url)
    signal openFolder(string url)
    signal openTag(string tag)
    signal refreshAbout()

    clip: true
    contentHeight: body.height + 48
    boundsBehavior: Flickable.StopAtBounds
    readonly property bool wide: width > 700

    Item {
        id: body
        width: Math.min(page.width - 48, 1240)
        x: (page.width - width) / 2
        y: 24
        height: wide ? Math.max(head.height + 28 + about.height, grid.height)
                     : head.height + 24 + grid.height + 32 + about.height

        Column {
            id: head
            width: wide ? (body.width >= 880 ? 300 : 260) : body.width
            spacing: 10
            CoverArt {
                id: avatar
                width: wide ? Math.min(200, parent.width) : 160; height: width
                x: wide ? 0 : (parent.width - width) / 2
                radius: width / 2
                decode: 400
                source: page.aboutOnline && page.aboutOnline.photo ? page.aboutOnline.photo : (page.artist ? page.artist.cover || "" : "")
            }
            Item { width: 1; height: 2 }
            Text {
                width: parent.width
                horizontalAlignment: wide ? Text.AlignLeft : Text.AlignHCenter
                text: "ARTISTA"; color: Theme.accentFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2; font.weight: Font.Bold; font.letterSpacing: 0.6
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                horizontalAlignment: wide ? Text.AlignLeft : Text.AlignHCenter
                text: page.artist ? page.artist.name : ""
                color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize - 2; font.weight: Theme.titleWeight
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                horizontalAlignment: wide ? Text.AlignLeft : Text.AlignHCenter
                text: about.subtitle !== "" ? about.subtitle + " · " + albumsLabel() : albumsLabel()
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
                function albumsLabel() { return page.albums.length + (page.albums.length === 1 ? " álbum" : " álbuns") }
            }
            Row {
                spacing: 8
                x: wide ? 0 : (parent.width - width) / 2
                FlatButton { text: "Reproduzir"; suggested: true; onClicked: page.playAll(false) }
                FlatButton { text: "Aleatório"; color: Theme.hover; onClicked: page.playAll(true) }
            }
        }

        InfoBar {
            id: about
            embedded: true
            kind: "artist"
            x: 0
            y: wide ? head.height + 28 : grid.y + grid.height + 32
            width: wide ? head.width : body.width
            height: implicitHeight
            subject: page.artist
            info: page.aboutInfo
            online: page.aboutOnline
            loading: page.aboutLoading
            onlineOff: page.aboutOff
            playingId: page.playingId
            onPlayTracks: (t, i) => page.playTracks(t, i)
            onOpenAlbum: (a) => page.openAlbum(a)
            onOpenLink: (url) => page.openLink(url)
            onOpenFolder: (url) => page.openFolder(url)
            onOpenTag: (tag) => page.openTag(tag)
            onRefreshOnline: page.refreshAbout()
        }

        // Albums: plain tiles (an artist has tens, not thousands).
        Flow {
            id: grid
            x: wide ? head.width + 32 : 0
            y: wide ? 0 : head.height + 24
            width: wide ? body.width - head.width - 32 : body.width
            readonly property int gap: Theme.compact ? 14 : 20
            readonly property int columns: Math.max(2, Math.floor((width + gap) / (Theme.tileMin + gap)))
            readonly property int tile: Math.floor((width - (columns - 1) * gap) / columns)
            spacing: gap
            Repeater {
                model: page.albums
                Item {
                    required property var modelData
                    width: grid.tile; height: grid.tile + 52
                    Column {
                        width: parent.width
                        spacing: 6
                        CoverArt {
                            width: grid.tile; height: grid.tile
                            decode: grid.tile
                            source: modelData.cover
                            hovered: am.containsMouse
                            scale: am.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: modelData.title; color: Theme.fg
                            font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: (modelData.year ? modelData.year + " · " : "") + modelData.tracks + (modelData.tracks === 1 ? " faixa" : " faixas")
                            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                        }
                    }
                    MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.openAlbum(modelData) }
                }
            }
        }
    }
}
