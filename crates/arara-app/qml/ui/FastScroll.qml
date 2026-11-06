import QtQuick
import AraraStyle

// Fast navigation for long lists and grids: a wide scroll bar whose thumb can
// be dragged (or the track clicked) to jump anywhere, plus an A–Z index to its
// left. While dragging, a bubble shows the letter (or year) under the view.
Item {
    id: fs
    property Flickable view: null
    // [{l: "A", row: 0}, …] — first item of each section, in view order.
    property var sections: []
    // function(index) -> label for the bubble while dragging the thumb
    property var labelAt: null
    readonly property bool hasIndex: sections.length > 1
    readonly property int maxLetters: Math.max(2, Math.floor(height / 15))
    // Too many sections (e.g. years) for the height: show every n-th.
    readonly property var shown: {
        if (sections.length <= maxLetters) return sections
        var step = Math.ceil(sections.length / maxLetters), out = []
        for (var i = 0; i < sections.length; i += step) out.push(sections[i])
        return out
    }
    property string bubble: ""
    property real bubbleY: 0

    width: hasIndex ? 40 : 16
    visible: !!view && view.contentHeight > view.height * 1.2

    function jumpTo(row) {
        if (!view) return
        view.positionViewAtIndex(row, 1 /* Beginning */)
    }
    function letterAt(y) {
        if (shown.length === 0) return -1
        var i = Math.floor((y - letters.y) / (letters.height / shown.length))
        return Math.max(0, Math.min(shown.length - 1, i))
    }
    function labelForView() {
        if (!view || !labelAt) return ""
        var i = view.indexAt(view.width / 2, view.contentY + Math.min(80, view.height / 3))
        return i >= 0 ? labelAt(i) : ""
    }

    // ---- A–Z index ----
    Column {
        id: letters
        visible: fs.hasIndex
        anchors { right: track.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
        width: 22
        Repeater {
            model: fs.shown
            Text {
                required property var modelData
                width: 22; height: Math.min(18, (fs.height - 16) / Math.max(1, fs.shown.length))
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: modelData.l.length > 2 ? "’" + modelData.l.slice(-2) : modelData.l
                color: fs.bubble === modelData.l ? Theme.accentFg : Theme.dimFg
                font.family: Theme.font; font.pointSize: Theme.fontSize - 3; font.weight: Font.DemiBold
            }
        }
    }
    MouseArea {
        anchors.fill: letters
        anchors.margins: -4
        visible: fs.hasIndex
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        function pick(y) {
            var i = fs.letterAt(y + letters.y - 4)
            if (i < 0) return
            var s = fs.shown[i]
            fs.bubble = s.l; fs.bubbleY = letters.y + y - 4
            fs.jumpTo(s.row)
        }
        onPressed: (m) => pick(m.y)
        onPositionChanged: (m) => { if (pressed) pick(m.y) }
        onReleased: fs.bubble = ""
        onCanceled: fs.bubble = ""
    }

    // ---- scroll bar ----
    Item {
        id: track
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 6; bottomMargin: 6 }
        width: 14
        readonly property real ratio: fs.view ? Math.min(1, fs.view.visibleArea.heightRatio) : 1
        readonly property real pos: fs.view ? Math.max(0, Math.min(1 - ratio, fs.view.visibleArea.yPosition)) : 0
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom }
            width: trackArea.containsMouse || trackArea.pressed ? 8 : 4; radius: width / 2
            color: Theme.hover
            Behavior on width { NumberAnimation { duration: 120 } }
        }
        Rectangle {
            id: thumb
            anchors.horizontalCenter: parent.horizontalCenter
            width: trackArea.containsMouse || trackArea.pressed ? 10 : 6; radius: width / 2
            height: Math.max(44, track.height * track.ratio)
            y: track.height <= height ? 0 : (track.pos / Math.max(0.0001, 1 - track.ratio)) * (track.height - height)
            color: trackArea.pressed ? Theme.accent : Theme.dimFg
            opacity: trackArea.pressed ? 1 : trackArea.containsMouse ? 0.8 : 0.45
            Behavior on width { NumberAnimation { duration: 120 } }
        }
        MouseArea {
            id: trackArea
            anchors.fill: parent
            anchors.leftMargin: -4
            hoverEnabled: true
            preventStealing: true
            property real grab: -1
            function scrollTo(thumbTop) {
                var v = fs.view
                var span = Math.max(1, track.height - thumb.height)
                var frac = Math.max(0, Math.min(1, thumbTop / span))
                var top = v.originY - v.topMargin
                var range = v.contentHeight + v.topMargin + v.bottomMargin - v.height
                v.contentY = top + frac * Math.max(0, range)
                fs.bubble = fs.labelForView()
                fs.bubbleY = track.y + thumb.y + thumb.height / 2
            }
            onPressed: (m) => {
                // On the thumb: drag it from where it was grabbed; elsewhere: jump there.
                grab = (m.y >= thumb.y && m.y <= thumb.y + thumb.height) ? m.y - thumb.y : thumb.height / 2
                scrollTo(m.y - grab)
            }
            onPositionChanged: (m) => { if (pressed) scrollTo(m.y - grab) }
            onReleased: fs.bubble = ""
            onCanceled: fs.bubble = ""
        }
    }

    // ---- bubble ----
    Rectangle {
        visible: fs.bubble !== ""
        anchors.right: parent.left; anchors.rightMargin: 10
        y: Math.max(0, Math.min(fs.height - height, fs.bubbleY - height / 2))
        width: Math.max(64, bubbleText.implicitWidth + 28); height: 64; radius: 32
        color: Theme.accent
        Text {
            id: bubbleText
            anchors.centerIn: parent
            text: fs.bubble; color: "white"
            font.family: Theme.font; font.pointSize: 24; font.weight: Font.Bold
        }
    }
}
