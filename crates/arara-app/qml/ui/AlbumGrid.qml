import QtQuick
import AraraStyle
import QtQuick.Controls.Basic as QQC

// Album grid. GridView only instantiates visible delegates and recycles
// them, and each cover is decoded at tile size on a worker thread, so memory
// stays flat no matter how large the library is.
GridView {
    QQC.ScrollBar.vertical: OverlayScrollBar {}
    id: grid
    property var albums: []
    signal openAlbum(var album)

    // As many columns as fit tiles of at least Theme.tileMin, then the tiles grow
    // to fill the row, so there is never a wide empty gutter.
    readonly property int gap: Theme.compact ? 14 : 20
    readonly property int columns: Math.max(2, Math.floor((width - 24 + gap) / (Theme.tileMin + gap)))
    readonly property int tile: Math.floor((width - 24) / columns) - gap
    cellWidth: Math.floor((width - 24) / columns)
    cellHeight: tile + 64
    leftMargin: 12; rightMargin: 12; topMargin: 18; bottomMargin: 18
    clip: true
    model: albums
    cacheBuffer: cellHeight * 2
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
        required property var modelData
        width: grid.cellWidth
        height: grid.cellHeight

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            width: grid.tile
            spacing: 6

            CoverArt {
                id: art
                width: grid.tile; height: grid.tile
                decode: grid.tile
                source: modelData.cover
                hovered: ma.containsMouse
                scale: ma.pressed ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
            Text {
                width: parent.width
                text: modelData.title
                color: Theme.fg; elide: Text.ElideRight
                font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: (modelData.artist || "") + (modelData.year ? " · " + modelData.year : "")
                color: Theme.dimFg; elide: Text.ElideRight
                font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: grid.openAlbum(modelData)
        }
    }
}
