import QtQuick
import AraraStyle

// Search results / song list (virtualized ListView).
Item {
    id: page
    property var results: []
    property string query: ""
    property int playingId: -1
    signal play(var tracks, int index)
    signal menuRequested(var track, real x, real y)
    signal starToggled(var track, bool starred)

    ListView {
        id: lv
        anchors.fill: parent
        anchors.margins: 0
        clip: true
        model: page.results
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        topMargin: 18; bottomMargin: 18
        delegate: Item {
            required property var modelData
            required property int index
            width: lv.width; height: 54
            Rectangle {
                anchors { fill: parent; leftMargin: Math.max(24, (lv.width - 900) / 2); rightMargin: anchors.leftMargin }
                color: Theme.cardBg
                radius: index === 0 || index === page.results.length - 1 ? Theme.cardRadius : 0
                clip: true
                TrackRow {
                    anchors.fill: parent
                    track: modelData; number: index; showArt: true
                    playing: modelData.id === page.playingId
                    onActivated: page.play(page.results, index)
                    onMenuRequested: (t, x, y) => page.menuRequested(t, x, y)
                    onStarToggled: (t, s) => page.starToggled(t, s)
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: page.results.length === 0
        spacing: 8
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Theme.glyph("search"); color: Theme.dimFg; font.pointSize: 48 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.query === "" ? "Pesquise músicas, artistas e álbuns" : "Nenhum resultado"
            color: Theme.fg; font.family: Theme.font; font.pointSize: 16; font.weight: Font.Bold
        }
    }
}
