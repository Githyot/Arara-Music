import QtQuick
import AraraStyle

// Album grid. GridView only instantiates visible delegates and recycles
// them, and each cover is decoded at tile size on a worker thread, so memory
// stays flat no matter how large the library is.
GridView {
    id: grid
    property var albums: []
    signal openAlbum(var album)

    readonly property int tile: 180
    readonly property int columns: Math.max(1, Math.floor((width - 24) / (tile + 24)))
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

            Rectangle {
                id: art
                width: grid.tile; height: grid.tile
                radius: Theme.radius + 2
                color: Theme.cardBg
                clip: true
                border.color: Theme.border; border.width: 0.5

                Image {
                    anchors.fill: parent
                    source: modelData.cover
                    sourceSize: Qt.size(grid.tile, grid.tile)
                    asynchronous: true
                    cache: false          // thumbnails are already on disk; don't pin them in RAM
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: modelData.cover === ""
                    text: Theme.glyph("lyrics"); color: Theme.dimFg; font.pointSize: 40
                }
                Rectangle { anchors.fill: parent; color: "white"; opacity: ma.containsMouse ? 0.08 : 0; radius: parent.radius }
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
