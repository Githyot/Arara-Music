import QtQuick
import QtQuick.Controls
import AraraStyle
import QtQuick.Controls.Basic as QQC

// Album details: big art + title on the left (stacks on narrow widths),
// boxed track list on the right.
Flickable {
    QQC.ScrollBar.vertical: OverlayScrollBar {}
    id: page
    property var album
    property var tracks: []
    property int playingId: -1
    signal play(var tracks, int index)
    signal menuRequested(var track, real x, real y)
    signal starToggled(var track, bool starred)
    signal openArtist(int artistId)
    // "Sobre o álbum" shown right on the page (left column, or under the tracks when narrow).
    property var aboutInfo: null
    property var aboutOnline: null
    property bool aboutLoading: false
    property bool aboutOff: false
    signal openLink(string url)
    signal openFolder(string url)
    signal refreshAbout()
    signal openTag(string tag)
    signal refreshCover(int albumId)
    signal chooseCover(int albumId)

    clip: true
    contentHeight: body.height + 48
    boundsBehavior: Flickable.StopAtBounds
    readonly property bool wide: width > 700

    // Real track numbers: a song missing from the library leaves its number
    // out (06, 09, 10…) and a quiet row says which ones are missing.
    function discOf(t) { return t && t.discNo > 0 ? t.discNo : 1 }
    readonly property bool multiDisc: {
        for (var i = 1; i < tracks.length; i++) if (discOf(tracks[i]) !== discOf(tracks[0])) return true
        return false
    }
    function discHeader(i) {
        if (!multiDisc) return ""
        if (i > 0 && discOf(tracks[i]) === discOf(tracks[i - 1])) return ""
        return "Disco " + discOf(tracks[i])
    }
    function gapText(i) {
        var t = tracks[i], cur = t && t.trackNo > 0 ? t.trackNo : 0
        if (!cur) return ""
        var prev = 0
        if (i > 0 && discOf(tracks[i - 1]) === discOf(t)) {
            prev = tracks[i - 1].trackNo > 0 ? tracks[i - 1].trackNo : -1
            if (prev < 0) return ""
        }
        var a = prev + 1, b = cur - 1
        if (b < a) return ""
        return a === b ? "Faixa " + a + " não está na biblioteca"
                       : "Faixas " + a + (b === a + 1 ? " e " : " a ") + b + " não estão na biblioteca"
    }

    Item {
        id: body
        width: Math.min(page.width - 48, 1000)
        x: (page.width - width) / 2
        y: 24
        height: wide ? Math.max(info.height + 28 + about.height, list.height) : info.height + 24 + list.height + 32 + about.height

        Column {
            id: info
            width: wide ? (body.width >= 880 ? 300 : 260) : body.width
            spacing: 10
            MotionCover {
                width: Math.min(wide ? parent.width : 260, parent.width); height: width
                x: wide ? 0 : (parent.width - width) / 2
                decode: 260
                source: page.album ? page.album.coverBig : ""
                albumId: page.album ? page.album.id : -1
                primary: true
                // Right-click on the art: the same cover menu as the "⋯" button.
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.RightButton
                    onClicked: (m) => coverMenu.openAt(parent, m.x, m.y)
                }
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
                FlatButton { id: moreBtn; icon: "more"; tip: "Capa do álbum"; onClicked: coverMenu.openAt(moreBtn, 0, moreBtn.height + 4) }
            }
        }

        InfoBar {
            id: about
            embedded: true
            kind: "album"
            x: 0
            y: wide ? info.height + 28 : list.y + list.height + 32
            width: wide ? info.width : body.width
            height: implicitHeight
            subject: page.album
            info: page.aboutInfo
            online: page.aboutOnline
            loading: page.aboutLoading
            onlineOff: page.aboutOff
            playingId: page.playingId
            onOpenLink: (url) => page.openLink(url)
            onOpenFolder: (url) => page.openFolder(url)
            onRefreshOnline: page.refreshAbout()
            onOpenTag: (tag) => page.openTag(tag)
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
                    Column {
                        id: entry
                        required property var modelData
                        required property int index
                        width: col.width
                        readonly property string disc: page.discHeader(index)
                        readonly property string gap: page.gapText(index)
                        // "Disco 2" when the album spans several discs.
                        Text {
                            visible: entry.disc !== ""
                            width: parent.width; height: visible ? 40 : 0
                            leftPadding: 14; verticalAlignment: Text.AlignBottom; bottomPadding: 6
                            text: entry.disc
                            color: Theme.dimFg
                            font.family: Theme.font; font.pointSize: Theme.fontSize - 1; font.weight: Font.DemiBold
                        }
                        // Songs of the album that are not in the library.
                        Item {
                            visible: entry.gap !== ""
                            width: parent.width; height: visible ? 30 : 0
                            Row {
                                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                spacing: 12
                                Text {
                                    width: 22; horizontalAlignment: Text.AlignHCenter
                                    text: "⋯"; color: Theme.dimFg; opacity: 0.7
                                    font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                                }
                                Text {
                                    text: entry.gap; color: Theme.dimFg; opacity: 0.85
                                    font.family: Theme.font; font.pointSize: Theme.fontSize - 2; font.italic: true
                                }
                            }
                        }
                        TrackRow {
                            width: col.width
                            track: entry.modelData
                            number: entry.index
                            label: entry.modelData.trackNo > 0 ? String(entry.modelData.trackNo) : ""
                            hideArtist: page.album && page.album.artist ? page.album.artist : ""
                            playing: entry.modelData.id === page.playingId
                            onActivated: page.play(page.tracks, entry.index)
                            onMenuRequested: (t, x, y) => page.menuRequested(t, x, y)
                            onStarToggled: (t, s) => page.starToggled(t, s)
                        }
                    }
                }
            }
        }
    }

    // Cover actions. The cover is voted from the album's own files; these fix
    // the rare album where that still picks the wrong picture.
    Popup {
        id: coverMenu
        width: 260
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        function openAt(item, px, py) {
            var p = item.mapToItem(Overlay.overlay, px, py)
            parent = Overlay.overlay
            x = Math.min(p.x, Overlay.overlay.width - width - 8); y = p.y
            open()
        }
        background: Rectangle { radius: Theme.popupRadius; color: Theme.popupBg; border.color: Theme.border }
        contentItem: Column {
            Repeater {
                model: [
                    { k: "refresh", t: "Procurar a capa de novo" },
                    { k: "choose", t: "Escolher imagem da capa…" }
                ]
                Rectangle {
                    required property var modelData
                    width: coverMenu.width - 12; height: 34; radius: Theme.material ? 0 : Theme.radius
                    color: cm.containsMouse ? Theme.hover : "transparent"
                    Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: modelData.t; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                    MouseArea {
                        id: cm; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            coverMenu.close()
                            if (!page.album) return
                            if (modelData.k === "refresh") page.refreshCover(page.album.id)
                            else page.chooseCover(page.album.id)
                        }
                    }
                }
            }
        }
    }
}
