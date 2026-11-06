import QtQuick
import AraraStyle

// Play queue: click to jump, ✕ to remove. Upcoming tracks after the current one.
ListView {
    id: lv
    property var queue: []
    property int current: -1
    property int side: 24
    property bool onDark: false
    signal jump(int index)
    signal removeAt(int index)
    signal moveItem(int from, int to)
    property DragReorder reorder: DragReorder { view: lv; onMoved: (f, t) => lv.moveItem(f, t) }

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
            anchors { fill: parent; leftMargin: lv.side; rightMargin: lv.side }
            radius: Theme.radius
            color: index === lv.current ? (lv.onDark ? Qt.rgba(1, 1, 1, 0.14) : Theme.selected) : "transparent"
            TrackRow {
                anchors.fill: parent
                color: "transparent"
                onDark: lv.onDark
                track: modelData; number: index; showArt: true
                playing: index === lv.current
                removable: index !== lv.current
                draggable: true
                dropMark: lv.reorder.mark(index)
                onDragStart: lv.reorder.start(index)
                onDragMove: (y) => lv.reorder.move(y)
                onDragEnd: lv.reorder.end()
                onActivated: lv.jump(index)
                onRemoveRequested: lv.removeAt(index)
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: lv.queue.length === 0
        text: "A fila está vazia"
        color: lv.onDark ? Qt.rgba(1, 1, 1, 0.6) : Theme.dimFg; font.family: Theme.font; font.pointSize: 14
    }
}
