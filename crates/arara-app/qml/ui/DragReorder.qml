import QtQuick

// Shared drag-to-reorder state for a ListView whose delegates are TrackRows
// with `draggable: true`. Rows report scene Y while dragging; we translate
// that to a target index, auto-scroll near the edges and emit `moved` on drop.
QtObject {
    id: dr
    property ListView view
    property int from: -1
    property int to: -1
    property real sceneY: 0
    signal moved(int from, int to)

    function start(i) { from = i; to = i }
    function move(y) {
        sceneY = y
        var local = view.mapFromItem(null, 0, y).y
        var i = view.indexAt(20, view.contentY + local)
        if (i < 0) i = local < view.height / 2 ? 0 : view.count - 1
        to = i
        scroller.running = local < 40 || local > view.height - 40
    }
    function end() {
        scroller.running = false
        if (from >= 0 && to >= 0 && from !== to) moved(from, to)
        from = -1; to = -1
    }
    function mark(i) { return from < 0 || i !== to || i === from ? -1 : (to < from ? 0 : 1) }

    property Timer scroller: Timer {
        interval: 16; repeat: true
        onTriggered: {
            var local = dr.view.mapFromItem(null, 0, dr.sceneY).y
            var step = local < 40 ? -12 : 12
            dr.view.contentY = Math.max(-dr.view.topMargin - (dr.view.headerItem ? dr.view.headerItem.height : 0),
                                        Math.min(dr.view.contentHeight - dr.view.height + dr.view.originY, dr.view.contentY + step))
            dr.move(dr.sceneY)
        }
    }
}
