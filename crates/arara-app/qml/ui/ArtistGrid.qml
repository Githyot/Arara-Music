import QtQuick
import AraraStyle
import QtQuick.Controls.Basic as QQC

// Artists as round avatars (cover of their latest album), like GNOME Music.
GridView {
    QQC.ScrollBar.vertical: OverlayScrollBar {}
    id: grid
    property var artists: []
    signal openArtist(var artist)

    readonly property int tile: Math.max(120, Theme.tileMin - 10)
    readonly property int columns: Math.max(1, Math.floor((width - 24) / (tile + 32)))
    cellWidth: Math.floor((width - 24) / columns)
    cellHeight: tile + 60
    leftMargin: 12; rightMargin: 12; topMargin: 18; bottomMargin: 18
    clip: true
    model: artists
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
        required property var modelData
        width: grid.cellWidth; height: grid.cellHeight
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Item {
                width: grid.tile; height: grid.tile
                // circle mask: a rounded rectangle with clip only clips to bounds in
                // Qt Quick, so draw the image inside a layer-free "ring" instead.
                Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.cardBg }
                Image {
                    id: img
                    anchors.fill: parent
                    source: modelData.cover
                    sourceSize: Qt.size(grid.tile, grid.tile)
                    asynchronous: true; cache: false
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }
                ShaderEffect {
                    anchors.fill: parent
                    visible: img.status === Image.Ready
                    property variant src: img
                    fragmentShader: "qrc:/qt/qml/AraraStyle/circle.frag.qsb"
                }
                Text {
                    anchors.centerIn: parent
                    visible: img.status !== Image.Ready
                    text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                    color: Theme.dimFg; font.family: Theme.font; font.pointSize: 40; font.weight: Font.Bold
                }
                Rectangle { anchors.fill: parent; radius: width / 2; color: "white"; opacity: ma.containsMouse ? 0.08 : 0 }
            }
            Text {
                width: grid.tile; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                text: modelData.name; color: Theme.fg
                font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
            }
            Text {
                width: grid.tile; horizontalAlignment: Text.AlignHCenter
                text: modelData.albums + (modelData.albums === 1 ? " álbum" : " álbuns"); color: Theme.dimFg
                font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: grid.openArtist(modelData) }
    }
}
