import QtQuick
import QtQuick.Controls
import AraraStyle

// Lyrics editor in two steps:
//  1. "Texto": paste or type the lyrics, one line per sung line.
//  2. "Sincronizar": play the song and press Enter at the start of each line
//     (Backspace undoes, ← goes back 5 s). Click a line's time to re-stamp it.
// Saving stores the LRC in the library (and optionally as song.lrc next to the
// file); "Enviar ao LRCLIB" shares it so other players get it too.
Rectangle {
    id: ed
    property var track: null
    property real position: 0
    property bool playing: false
    property string step: "text"
    property var lines: []      // [{ text, t }]  t = -1 when not stamped
    property int cursor: 0
    property bool saved: false
    property bool publishing: false
    property bool saveBeside: true      // Preferences › Letras › "Salvar ao lado das músicas"
    signal seek(real ms)
    signal togglePlay()
    signal save(string text, bool synced, bool sidecar)
    signal publish()
    signal close()

    color: Theme.windowBg
    focus: visible

    function openWith(t, lyrics) {
        track = t; saved = false; publishing = false; step = "text"; cursor = 0
        sidecar.checked = saveBeside
        if (lyrics.kind === "synced") {
            lines = lyrics.lines.filter(function (l) { return l.text !== "" }).map(function (l) { return { text: l.text, t: l.t } })
            editor.text = lines.map(function (l) { return l.text }).join("\n")
        } else {
            editor.text = lyrics.kind === "plain" ? lyrics.text : ""
            lines = []
        }
        visible = true
        editor.forceActiveFocus()
    }
    function toSync() {
        var old = {}
        lines.forEach(function (l) { old[l.text] = old[l.text] || l.t })
        var used = {}
        lines = editor.text.split("\n").map(function (s) { return s.trim() }).filter(function (s) { return s !== "" })
            .map(function (s) { var t = (old[s] !== undefined && !used[s]) ? old[s] : -1; used[s] = true; return { text: s, t: t } })
        cursor = Math.max(0, lines.findIndex(function (l) { return l.t < 0 }))
        step = "sync"
        ed.forceActiveFocus()
    }
    function mark() {
        if (cursor >= lines.length) return
        var l = lines.slice(); l[cursor] = { text: l[cursor].text, t: Math.round(position) }; lines = l
        cursor++; list.positionViewAtIndex(Math.min(cursor, lines.length - 1), ListView.Center)
    }
    function undo() {
        if (cursor <= 0) return
        cursor--
        var l = lines.slice(); l[cursor] = { text: l[cursor].text, t: -1 }; lines = l
        seek(Math.max(0, cursor > 0 ? lines[cursor - 1].t : 0))
    }
    readonly property bool allStamped: lines.length > 0 && lines.every(function (l) { return l.t >= 0 })
    function fmt(ms) {
        if (ms < 0) return "--:--.--"
        var s = Math.floor(ms / 1000), cs = Math.floor((ms % 1000) / 10)
        return ("0" + Math.floor(s / 60)).slice(-2) + ":" + ("0" + s % 60).slice(-2) + "." + ("0" + cs).slice(-2)
    }
    function lrc() {
        var sorted = lines.slice().sort(function (a, b) { return a.t - b.t })
        return sorted.map(function (l) { return "[" + fmt(l.t) + "]" + l.text }).join("\n") + "\n"
    }
    function doSave() {
        if (step === "sync" && allStamped) save(lrc(), true, sidecar.checked)
        else save(step === "sync" ? lines.map(function (l) { return l.text }).join("\n") : editor.text, false, sidecar.checked)
        saved = true
    }

    Keys.onPressed: (e) => {
        if (step !== "sync") return
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { mark(); e.accepted = true }
        else if (e.key === Qt.Key_Backspace) { undo(); e.accepted = true }
        else if (e.key === Qt.Key_Left) { seek(Math.max(0, position - 5000)); e.accepted = true }
        else if (e.key === Qt.Key_Space) { togglePlay(); e.accepted = true }
    }

    HeaderBar {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        title: "Editar letra"
        subtitle: ed.track ? ed.track.title + " — " + ed.track.artist : ""
        showControls: false
        leading: [ FlatButton { text: "Cancelar"; onClicked: ed.close() } ]
        trailing: [ FlatButton { text: "Salvar"; suggested: true; onClicked: ed.doSave() } ]
    }

    // step switcher
    Rectangle {
        id: switcher
        anchors { horizontalCenter: parent.horizontalCenter; top: head.bottom; topMargin: 14 }
        width: 280; height: 34; radius: Theme.radius; color: Theme.hover
        Row {
            anchors.fill: parent; anchors.margins: 3
            Repeater {
                model: [{ k: "text", t: "1. Texto" }, { k: "sync", t: "2. Sincronizar" }]
                Rectangle {
                    required property var modelData
                    width: (switcher.width - 6) / 2; height: switcher.height - 6; radius: Theme.radius - 2
                    color: ed.step === modelData.k ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.15) : "#ffffff") : "transparent"
                    Text { anchors.centerIn: parent; text: modelData.t; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; onClicked: modelData.k === "sync" ? ed.toSync() : (ed.step = "text") }
                }
            }
        }
    }

    // ---- step 1: text ----
    Rectangle {
        visible: ed.step === "text"
        anchors { left: parent.left; right: parent.right; top: switcher.bottom; bottom: footer.top; margins: 24 }
        anchors.leftMargin: Math.max(24, (parent.width - 760) / 2); anchors.rightMargin: anchors.leftMargin
        radius: Theme.cardRadius; color: Theme.cardBg
        border.color: editor.activeFocus ? Theme.accent : Theme.border; border.width: editor.activeFocus ? 2 : 1
        Flickable {
            id: flick
            anchors.fill: parent; anchors.margins: 14
            contentHeight: editor.implicitHeight
            clip: true
            TextArea.flickable: TextArea {
                id: editor
                wrapMode: TextEdit.Wrap
                color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: "white"
                font.family: Theme.font; font.pointSize: 14
                placeholderText: "Cole ou digite a letra aqui, uma linha por verso…"
                placeholderTextColor: Theme.dimFg
                background: null
            }
        }
    }

    // ---- step 2: sync ----
    ListView {
        id: list
        visible: ed.step === "sync"
        anchors { left: parent.left; right: parent.right; top: switcher.bottom; bottom: syncBar.top; topMargin: 12 }
        anchors.leftMargin: Math.max(24, (parent.width - 760) / 2); anchors.rightMargin: anchors.leftMargin
        clip: true
        model: ed.lines
        spacing: 2
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: list.width; height: 44; radius: Theme.radius
            color: index === ed.cursor ? Theme.selected : "transparent"
            Rectangle {
                id: stamp
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                width: 92; height: 28; radius: Theme.radius
                color: sm.containsMouse ? Theme.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: ed.fmt(modelData.t)
                    color: modelData.t >= 0 ? Theme.accentFg : Theme.dimFg
                    font.family: "monospace"; font.pointSize: Theme.fontSize
                }
                // click the time: jump there; double-click: re-stamp from here
                MouseArea {
                    id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: if (modelData.t >= 0) ed.seek(modelData.t)
                    onDoubleClicked: { ed.cursor = index; ed.forceActiveFocus() }
                }
            }
            Text {
                anchors { left: stamp.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: modelData.text; elide: Text.ElideRight
                color: index === ed.cursor ? Theme.fg : (modelData.t >= 0 ? Theme.fg : Theme.dimFg)
                font.family: Theme.font; font.pointSize: index === ed.cursor ? 15 : 13
                font.weight: index === ed.cursor ? Font.Bold : Font.Normal
            }
        }
    }
    Rectangle {
        id: syncBar
        visible: ed.step === "sync"
        anchors { left: parent.left; right: parent.right; bottom: footer.top }
        height: visible ? 64 : 0; color: "transparent"
        Row {
            anchors.centerIn: parent
            spacing: 10
            FlatButton { icon: "undo"; circular: true; onClicked: ed.undo() }
            FlatButton { icon: ed.playing ? "pause" : "play"; circular: true; size: 40; onClicked: ed.togglePlay() }
            FlatButton {
                text: ed.cursor < ed.lines.length ? "Marcar linha  ⏎" : "Tudo marcado"
                suggested: ed.cursor < ed.lines.length
                onClicked: ed.mark()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ed.fmt(ed.position) + "   ·   " + ed.lines.filter(function (l) { return l.t >= 0 }).length + "/" + ed.lines.length
                color: Theme.dimFg; font.family: "monospace"; font.pointSize: Theme.fontSize
            }
        }
    }

    // ---- footer ----
    Rectangle {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 56; color: Theme.headerBg
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.border; opacity: 0.6 }
        Row {
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 10
            visible: !(ed.track && ed.track.remote)   // no file next to a streamed song
            Rectangle {
                id: sidecar
                property bool checked: false
                width: 20; height: 20; radius: 5; anchors.verticalCenter: parent.verticalCenter
                color: checked ? Theme.accent : "transparent"; border.color: checked ? Theme.accent : Theme.dimFg; border.width: 2
                Icon { anchors.centerIn: parent; visible: sidecar.checked; name: "check"; size: 14; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: sidecar.checked = !sidecar.checked }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Salvar também como arquivo .lrc ao lado da música"
                color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize
                MouseArea { anchors.fill: parent; onClicked: sidecar.checked = !sidecar.checked }
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !ed.saved || !ed.allStamped
                text: ed.allStamped ? "Salve para poder enviar" : "Sincronize todas as linhas para enviar ao LRCLIB"
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
            FlatButton {
                text: ed.publishing ? "Enviando…" : "Enviar ao LRCLIB"
                color: Theme.hover
                opacity: ed.saved && ed.allStamped && !ed.publishing ? 1 : 0.45
                onClicked: if (ed.saved && ed.allStamped && !ed.publishing) { ed.publishing = true; ed.publish() }
            }
        }
    }
}
