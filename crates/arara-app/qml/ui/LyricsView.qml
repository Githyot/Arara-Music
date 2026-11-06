import QtQuick
import AraraStyle

// Karaoke lyrics. The current line is centered and its words fill with the
// accent color as they are sung (word timings from enhanced LRC, or
// interpolated across the line for plain synced LRC). Click a line to seek.
Item {
    id: view
    property var lyrics: ({ kind: "none" })
    property real position: 0
    property bool playing: false
    // Playback position shifted by the user's sync adjustment. The player only
    // reports its position every ~100 ms, so between reports the clock runs on
    // by itself every frame: the words fill and grow smoothly, not in steps.
    property real at: position + Prefs.lyricsOffset
    property real _base: 0
    property real _baseT: 0
    onPositionChanged: {
        _base = position; _baseT = Date.now()
        if (!clock.running) at = position + Prefs.lyricsOffset
    }
    FrameAnimation {
        id: clock
        running: view.playing && view.visible && view.lyrics.kind === "synced"
        onTriggered: view.at = view._base + Math.min(400, Date.now() - view._baseT) + Prefs.lyricsOffset
        onRunningChanged: if (!running) view.at = view.position + Prefs.lyricsOffset
    }
    property bool loading: false
    // Lyrics screen: white text over the blurred cover, bigger type.
    property bool onDark: false
    property int baseActive: 22
    property int baseLine: 18
    readonly property real activeSize: Math.round(baseActive * Prefs.lyricsScale * Theme.fontScale)
    readonly property real lineSize: Math.round(baseLine * Prefs.lyricsScale * Theme.fontScale)
    readonly property color ink: onDark ? "white" : Theme.fg
    readonly property color dim: onDark ? Qt.rgba(1, 1, 1, 0.55) : Theme.dimFg
    property int align: Text.AlignLeft
    // Small embedded view (player panel): no "add lyrics" button, smaller note text.
    property bool showAddButton: true
    property bool compact: false
    signal seek(real ms)

    readonly property var lines: lyrics.kind === "synced" ? lyrics.lines : []
    readonly property int current: {
        var lo = 0, hi = lines.length - 1, ans = -1
        while (lo <= hi) { var mid = (lo + hi) >> 1; if (lines[mid].t <= at) { ans = mid; lo = mid + 1 } else hi = mid - 1 }
        return ans
    }

    // Apple-Music-like motion: every line has the same font, the current one is
    // scaled up and bright, the rest shrink and fade; when the line changes the
    // view jumps and each line glides into place with a small stagger.
    // Duets: the second singer's lines sit on the right, "(…)" are background vocals.
    property bool browsing: false
    Timer { id: browseTimer; interval: 3000; onTriggered: { view.browsing = false; view.follow(true) } }
    signal stepped(real delta, int from)
    function follow(animated) {
        if (current < 0 || lv.count === 0 || browsing) return
        var old = lv.contentY
        lv.positionViewAtIndex(current, ListView.Beginning)
        var dest = Math.max(lv.originY - lv.topMargin, lv.contentY - lv.height * 0.28)
        lv.contentY = dest
        var delta = dest - old
        if (animated && Math.abs(delta) > 0.5 && Math.abs(delta) < lv.height) view.stepped(delta, current)
    }
    onCurrentChanged: follow(true)
    onLinesChanged: Qt.callLater(function () { view.browsing = false; view.follow(false) })
    onHeightChanged: Qt.callLater(function () { view.follow(false) })

    ListView {
        id: lv
        anchors.fill: parent
        visible: view.lyrics.kind === "synced"
        model: view.lines
        clip: true
        spacing: Math.round(view.activeSize * 0.75)
        interactive: true
        boundsBehavior: Flickable.StopAtBounds
        topMargin: height * 0.3; bottomMargin: height * 0.7
        cacheBuffer: 2000
        // Lines dissolve at the top and bottom edges instead of being cut off.
        layer.enabled: true
        layer.effect: ShaderEffect {
            property real fadeTop: view.compact ? 0.2 : 0.12
            property real fadeBottom: view.compact ? 0.2 : 0.16
            fragmentShader: "qrc:/qt/qml/AraraStyle/fade.frag.qsb"
        }
        onMovementStarted: { view.browsing = true; browseTimer.stop() }
        onMovementEnded: browseTimer.restart()

        delegate: Item {
            id: lineItem
            required property var modelData
            required property int index
            readonly property bool active: index === view.current
            readonly property bool past: index < view.current
            readonly property int voice: modelData.v || 0
            readonly property bool onRight: voice === 1 && Prefs.lyricsDuets
            readonly property bool bg: voice === 2
            readonly property real maxW: lv.width - 48 - (view.hasDuet ? lv.width * 0.1 : 0)
            width: lv.width
            height: flow.height * (bg ? 0.75 : 1)
            // 1 while this is the line being sung; eases back to 0 after it, so
            // the raised words settle down instead of snapping.
            property real live: active ? 1 : 0
            Behavior on live { NumberAnimation { duration: Theme.ms(520); easing.type: Easing.OutCubic } }

            transform: Translate { id: glide }
            Connections {
                target: view
                function onStepped(delta, from) {
                    var k = lineItem.index - from + 1
                    if (k < 0 || k > 12) return
                    glideAnim.stop(); glide.y = delta; pause.duration = k * 45; glideAnim.start()
                }
            }
            SequentialAnimation {
                id: glideAnim
                PauseAnimation { id: pause }
                NumberAnimation { target: glide; property: "y"; to: 0; duration: Theme.ms(620); easing.type: Easing.OutCubic }
            }

            TextMetrics { id: tm; font: probe.font; text: lineItem.modelData.text || "♪" }
            Text { id: probe; visible: false; font.family: Theme.font; font.pointSize: view.activeSize; font.weight: Font.Bold }
            // Width of one space (measured between letters: a lone space measures 0).
            TextMetrics { id: pairTm; font: probe.font; text: "n n" }
            TextMetrics { id: nnTm; font: probe.font; text: "nn" }
            readonly property real spaceW: Math.max(0, pairTm.advanceWidth - nnTm.advanceWidth)

            Flow {
                id: flow
                width: Math.min(lineItem.maxW, tm.advanceWidth * 1.05 + 8)
                x: lineItem.onRight ? lineItem.width - width - 24 : 24
                spacing: 0
                scale: lineItem.active ? 1 : (lineItem.bg ? 0.62 : view.lineSize / view.activeSize)
                transformOrigin: lineItem.onRight ? Item.TopRight : Item.TopLeft
                opacity: lineItem.active ? 1 : Math.max(0.16, (lineItem.past ? 0.42 : 0.5) - Math.abs(lineItem.index - view.current) * 0.05)
                Behavior on scale { NumberAnimation { duration: Theme.ms(480); easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 400 } }
                Repeater {
                    model: lineItem.modelData.w.length > 0 ? lineItem.modelData.w : [[lineItem.modelData.t, lineItem.modelData.e, lineItem.modelData.text || "♪"]]
                    Item {
                        id: word
                        required property var modelData
                        readonly property real p: !lineItem.active ? (lineItem.past ? 1 : 0)
                            : Math.max(0, Math.min(1, (view.at - modelData[0]) / Math.max(1, modelData[1] - modelData[0])))
                        // Apple-Music-like: as a word is sung it rises a little and
                        // grows a touch; held (long) words swell a bit more while held.
                        readonly property real ease: 1 - Math.pow(1 - p, 3)
                        readonly property bool held: modelData[1] - modelData[0] > 900
                        readonly property string txt: String(modelData[2]).replace(/\s+$/, "")
                        readonly property bool spaced: txt.length < String(modelData[2]).length
                        // The trailing space sits outside the part that grows, so
                        // neighbouring words never touch while they swell.
                        // Room for the growth is reserved up front (constant per word),
                        // so the line never reflows while it is sung.
                        readonly property real room: base.implicitWidth * 0.04
                        width: glyphs.width + room + (spaced ? lineItem.spaceW : 0); height: glyphs.height
                        Item {
                            id: glyphs
                            x: word.room / 2
                            width: base.implicitWidth; height: base.implicitHeight
                            transformOrigin: Item.Bottom
                            scale: 1 + lineItem.live * (0.04 * word.ease + (word.held ? 0.06 * Math.sin(Math.PI * word.p) : 0))
                            transform: Translate { y: -glyphs.height * 0.065 * lineItem.live * word.ease }
                            Text {
                                id: base
                                text: word.txt
                                color: lineItem.active ? view.ink : view.dim
                                opacity: lineItem.active ? 0.4 : 1
                                font: probe.font
                            }
                            // The sung part: same text, clipped to progress, fully bright.
                            Item {
                                visible: lineItem.active || lineItem.live > 0.01
                                width: base.width * word.p; height: base.height; clip: true
                                opacity: lineItem.live
                                Text { text: word.txt; color: view.onDark ? "white" : Theme.accentFg; font: probe.font }
                            }
                        }
                    }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { view.browsing = false; view.seek(lineItem.modelData.t) } }
        }
    }
    readonly property bool hasDuet: {
        for (var i = 0; i < lines.length; i++) if (lines[i].v === 1) return true
        return false
    }

    // Words without timings: centered, with a note, and scrolled along with
    // the song (proportionally) so they still roughly follow the music.
    property real duration: 0
    Flickable {
        id: plainFlick
        anchors.fill: parent
        visible: view.lyrics.kind === "plain"
        contentHeight: plainCol.height + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        readonly property real range: Math.max(0, contentHeight - height)
        property bool userScrolled: false
        onMovementStarted: userScrolled = true
        Connections {
            target: view
            function onLyricsChanged() { plainFlick.userScrolled = false; plainFlick.contentY = 0 }
        }
        // Follow the song: keep the line being sung (by proportion) in the middle.
        Binding {
            target: plainFlick; property: "contentY"
            when: !plainFlick.userScrolled && !plainFlick.moving && view.duration > 0 && plainFlick.range > 0
            value: Math.max(0, Math.min(plainFlick.range, (view.position / view.duration) * (plainFlick.contentHeight) - plainFlick.height * 0.4))
            restoreMode: Binding.RestoreNone
        }
        Behavior on contentY { enabled: !plainFlick.moving; NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }
        Column {
            id: plainCol
            y: Math.max(24, (plainFlick.height - height) / 2)
            x: 24; width: parent.width - 48
            spacing: 18
            Text {
                width: parent.width
                visible: !view.compact
                text: "Letra sem sincronia: ela rola junto com a música, mas sem marcar cada palavra"
                wrapMode: Text.Wrap
                color: view.dim; font.family: Theme.font; font.pointSize: Theme.fontSize
            }
            Text {
                id: plain
                width: parent.width
                text: view.lyrics.text || ""
                wrapMode: Text.Wrap
                color: view.ink; font.family: Theme.font; font.pointSize: view.compact ? view.lineSize : Math.round((view.onDark ? 22 : 16) * Prefs.lyricsScale * Theme.fontScale); font.weight: view.onDark ? Font.DemiBold : Font.Normal; lineHeight: 1.35
            }
        }
    }

    signal addLyrics()
    FlatButton {
        anchors { horizontalCenter: parent.horizontalCenter; top: noneText.bottom; topMargin: 14 }
        visible: view.showAddButton && view.lyrics.kind === "none" && !view.loading
        text: "Adicionar letra"; color: Theme.hover
        onClicked: view.addLyrics()
    }
    Text {
        id: noneText
        anchors.centerIn: parent
        visible: view.lyrics.kind === "none"
        text: view.loading ? "Buscando letra…" : "Sem letra para esta música"
        color: view.dim; font.family: Theme.font; font.pointSize: view.compact ? Theme.fontSize - 1 : 14
    }
}
