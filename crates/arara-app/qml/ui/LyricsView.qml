import QtQuick
import AraraStyle

// Karaoke lyrics. The current line is centered and its words fill with the
// accent color as they are sung (word timings from enhanced LRC, or
// interpolated across the line for plain synced LRC). Click a line to seek.
Item {
    id: view
    property var lyrics: ({ kind: "none" })
    property real position: 0
    property bool loading: false
    signal seek(real ms)

    readonly property var lines: lyrics.kind === "synced" ? lyrics.lines : []
    readonly property int current: {
        var lo = 0, hi = lines.length - 1, ans = -1
        while (lo <= hi) { var mid = (lo + hi) >> 1; if (lines[mid].t <= position) { ans = mid; lo = mid + 1 } else hi = mid - 1 }
        return ans
    }

    ListView {
        id: lv
        anchors.fill: parent
        visible: view.lyrics.kind === "synced"
        model: view.lines
        clip: true
        spacing: 14
        interactive: true
        currentIndex: view.current
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: height * 0.4
        preferredHighlightEnd: height * 0.4 + 60
        highlightMoveDuration: 350
        topMargin: height * 0.4; bottomMargin: height * 0.5

        delegate: Item {
            id: lineItem
            required property var modelData
            required property int index
            readonly property bool active: index === view.current
            readonly property bool past: index < view.current
            width: lv.width
            height: flow.height

            Flow {
                id: flow
                width: parent.width - 48
                x: 24
                spacing: 0
                Repeater {
                    model: lineItem.modelData.w.length > 0 ? lineItem.modelData.w : [[lineItem.modelData.t, lineItem.modelData.e, lineItem.modelData.text || "♪"]]
                    Item {
                        required property var modelData
                        readonly property real p: !lineItem.active ? (lineItem.past ? 1 : 0)
                            : Math.max(0, Math.min(1, (view.position - modelData[0]) / Math.max(1, modelData[1] - modelData[0])))
                        width: base.implicitWidth; height: base.implicitHeight
                        Text {
                            id: base
                            text: modelData[2]
                            color: lineItem.active ? Theme.fg : Theme.dimFg
                            opacity: lineItem.active ? 0.45 : (lineItem.past ? 0.5 : 0.7)
                            font.family: Theme.font; font.pointSize: lineItem.active ? 22 : 18; font.weight: Font.Bold
                        }
                        // The "sung" part: same text, clipped to progress, in accent color.
                        Item {
                            visible: lineItem.active
                            width: base.width * parent.p; height: base.height; clip: true
                            Text {
                                text: modelData[2]; color: Theme.accentFg
                                font: base.font
                            }
                        }
                    }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.seek(lineItem.modelData.t) }
        }
    }

    Flickable {
        anchors.fill: parent
        visible: view.lyrics.kind === "plain"
        contentHeight: plain.height + 48
        clip: true
        Text {
            id: plain
            y: 24; x: 24; width: parent.width - 48
            text: view.lyrics.text || ""
            wrapMode: Text.Wrap
            color: Theme.fg; font.family: Theme.font; font.pointSize: 16; lineHeight: 1.3
        }
    }

    Text {
        anchors.centerIn: parent
        visible: view.lyrics.kind === "none"
        text: view.loading ? "Buscando letra…" : "Sem letra para esta música"
        color: Theme.dimFg; font.family: Theme.font; font.pointSize: 14
    }
}
