import QtQuick
import AraraStyle

// Play queue: click to jump, ✕ to remove. Upcoming tracks after the current one.
ListView {
    id: lv
    property var queue: []
    property int current: -1
    signal jump(int index)
    signal removeAt(int index)

    clip: true
    model: queue
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds
    topMargin: 12; bottomMargin: 12
    Component.onCompleted: positionViewAtIndex(Math.max(0, current), ListView.Beginning)
    onVisibleChanged: if (visible) positionViewAtIndex(Math.max(0, current), ListView.Beginning)

    delegate: Item {
        required property var modelData
        required property int index
        width: lv.width; height: 54
        opacity: index < lv.current ? 0.55 : 1
        Rectangle {
            anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
            radius: Theme.radius
            color: index === lv.current ? Theme.selected : "transparent"
            TrackRow {
                anchors.fill: parent
                color: "transparent"
                track: modelData; number: index; showArt: true
                playing: index === lv.current
                removable: index !== lv.current
                onActivated: lv.jump(index)
                onRemoveRequested: lv.removeAt(index)
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: lv.queue.length === 0
        text: "A fila está vazia"
        color: Theme.dimFg; font.family: Theme.font; font.pointSize: 14
    }
}
