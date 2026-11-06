import QtQuick
import AraraStyle

// Album details: big art + title on the left (stacks on narrow widths),
// boxed track list on the right.
Flickable {
    id: page
    property var album
    property var tracks: []
    property int playingId: -1
    signal play(var tracks, int index)
    signal menuRequested(var track, real x, real y)
    signal starToggled(var track, bool starred)
    signal openArtist(int artistId)

    clip: true
    contentHeight: body.height + 48
    boundsBehavior: Flickable.StopAtBounds
    readonly property bool wide: width > 760

    Item {
        id: body
        width: Math.min(page.width - 48, 1000)
        x: (page.width - width) / 2
        y: 24
        height: wide ? Math.max(info.height, list.height) : info.height + 24 + list.height

        Column {
            id: info
            width: wide ? 260 : body.width
            spacing: 10
            CoverArt {
                width: Math.min(260, parent.width); height: width
                x: wide ? 0 : (parent.width - width) / 2
                decode: 260
                source: page.album ? page.album.coverBig : ""
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                horizontalAlignment: wide ? Text.AlignLeft : Text.AlignHCenter
                text: page.album ? page.album.title : ""
                color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize - 2; font.weight: Theme.titleWeight
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                horizontalAlignment: wide ? Text.AlignLeft : Text.AlignHCenter
                text: page.album ? (page.album.artist || "") + (page.album.year ? " · " + page.album.year : "") + " · " + page.tracks.length + " faixas" : ""
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: if (page.album && page.album.artistId) page.openArtist(page.album.artistId)
                }
            }
            Row {
                spacing: 8
                x: wide ? 0 : (parent.width - width) / 2
                FlatButton { text: "Reproduzir"; suggested: true; onClicked: page.play(page.tracks, 0) }
                FlatButton {
                    text: "Aleatório"; color: Theme.hover
                    onClicked: {
                        var t = page.tracks.slice()
                        for (var i = t.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var x = t[i]; t[i] = t[j]; t[j] = x }
                        page.play(t, 0)
                    }
                }
            }
        }

        Rectangle {
            id: list
            x: wide ? info.width + 32 : 0
            y: wide ? 0 : info.height + 24
            width: wide ? body.width - info.width - 32 : body.width
            height: col.height
            radius: Theme.cardRadius
            color: Theme.cardBg
            border.color: Theme.border; border.width: Theme.dark ? 0 : 1
            clip: true
            Column {
                id: col
                width: parent.width
                Repeater {
                    model: page.tracks
                    TrackRow {
                        required property var modelData
                        required property int index
                        width: col.width
                        track: modelData
                        number: index
                        playing: modelData.id === page.playingId
                        onActivated: page.play(page.tracks, index)
                        onMenuRequested: (t, x, y) => page.menuRequested(t, x, y)
                        onStarToggled: (t, s) => page.starToggled(t, s)
                    }
                }
            }
        }
    }
}
