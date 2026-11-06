import QtQuick
import AraraStyle

// "Música livre": search Jamendo and the Internet Archive (Creative Commons /
// public domain only), play straight away, or download into the library
// together with the synced lyrics (.lrc).
Item {
    id: page
    property var results: []
    property var errors: []
    property bool searching: false
    property string lastQuery: ""
    property string jamendoKey: ""
    // id -> { state: "queued"|"downloading"|"done"|"failed", pct, msg }
    property var dl: ({})
    property int playingIndex: -1
    signal play(var tracks, int index)
    signal download(var track)
    signal cancel(string id)
    signal saveKey(string key)

    readonly property int side: Math.max(24, (width - 900) / 2)

    function search(q) {
        q = q.trim()
        if (q === "") return
        lastQuery = q; searching = true; results = []; errors = []
        library.searchFree(q)
    }
    function setResults(q, json, errs) {
        if (q !== lastQuery) return
        results = JSON.parse(json); errors = JSON.parse(errs); searching = false
    }
    function onEvent(id, kind, pct, msg) {
        var d = Object.assign({}, dl)
        var st = kind === "started" || kind === "progress" ? "downloading" : kind === "done" || kind === "here" ? "done" : kind === "failed" ? "failed" : kind === "cancelled" ? "" : "queued"
        d[id] = { state: st, pct: pct, msg: msg }
        dl = d
    }
    function markQueued(id) { var d = Object.assign({}, dl); d[id] = { state: "queued", pct: 0, msg: "" }; dl = d }
    // Player track objects for free results (no library id: lyrics come from LRCLIB by name).
    function asTracks() {
        return results.map(function (r) {
            return { id: 0, free: true, url: r.stream_url, title: r.title, artist: r.artist, album: r.album,
                     duration: r.duration_ms, cover: r.cover_url, coverBig: r.cover_url, remote: true }
        })
    }

    // ---- header: search + key ----
    Column {
        id: head
        x: page.side; y: 18
        width: page.width - 2 * page.side
        spacing: 10
        Row {
            spacing: 10
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "download"; size: 22; color: Theme.accentFg }
            Text { text: "Música livre"; color: Theme.fg; font.family: Theme.displayFont; font.pointSize: Theme.titleSize; font.weight: Theme.titleWeight }
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: "Músicas com licença Creative Commons ou em domínio público, do Jamendo e do Internet Archive. Toque na hora ou baixe para a sua biblioteca, com a letra sincronizada quando houver."
            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
        }
        Rectangle {
            width: parent.width; height: 40; radius: Theme.radius
            color: Theme.hover
            border.color: input.activeFocus ? Theme.accent : "transparent"; border.width: 2
            Icon { id: sicon; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } name: "search"; size: 16; color: Theme.dimFg }
            TextInput {
                id: input
                anchors { left: sicon.right; right: goBtn.left; leftMargin: 10; rightMargin: 8; verticalCenter: parent.verticalCenter }
                color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: "white"
                font.family: Theme.font; font.pointSize: Theme.fontSize + 1
                clip: true
                onAccepted: page.search(text)
                Text { visible: !input.text && !input.activeFocus; text: "Artista, música, gênero (ex.: forró, chorinho, lo-fi)"; color: Theme.dimFg; font: input.font }
            }
            FlatButton { id: goBtn; anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter } text: "Buscar"; suggested: true; size: 32; onClicked: page.search(input.text) }
        }
        // Jamendo needs a free key (client id); without it only the Internet Archive is searched.
        Rectangle {
            visible: page.jamendoKey === ""
            width: parent.width; height: keyRow.height + 20; radius: Theme.radius
            color: Theme.cardBg
            Column {
                id: keyRow
                x: 12; y: 10; width: parent.width - 24; spacing: 6
                Text {
                    width: parent.width; wrapMode: Text.Wrap; textFormat: Text.StyledText
                    text: "Para incluir o <b>Jamendo</b>, crie uma chave grátis em devportal.jamendo.com (\"client id\") e cole aqui. Sem ela, a busca usa só o Internet Archive."
                    color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    onLinkActivated: (l) => Qt.openUrlExternally(l)
                }
                Row {
                    spacing: 8
                    Rectangle {
                        width: Math.min(260, keyRow.width - 120); height: 32; radius: Theme.radius; color: Theme.hover
                        TextInput {
                            id: keyInput
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            verticalAlignment: TextInput.AlignVCenter; clip: true
                            color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: !keyInput.text; text: "client id"; color: Theme.dimFg; font: keyInput.font }
                        }
                    }
                    FlatButton { text: "Salvar"; size: 32; enabled: keyInput.text.trim() !== ""; onClicked: page.saveKey(keyInput.text.trim()) }
                    FlatButton { text: "Abrir o site"; size: 32; onClicked: Qt.openUrlExternally("https://devportal.jamendo.com/") }
                }
            }
        }
    }

    // ---- results ----
    ListView {
        id: lv
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; topMargin: 14 }
        clip: true
        model: page.results
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: 18
        header: Item {
            width: lv.width; height: (page.errors.length ? errText.height + 8 : 0) + (page.results.length ? 28 : 0)
            Text {
                id: errText
                visible: page.errors.length > 0
                x: page.side; width: lv.width - 2 * page.side; wrapMode: Text.Wrap
                text: "Não deu para buscar em: " + page.errors.join(" · ")
                color: Theme.destructive; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
            Text {
                visible: page.results.length > 0
                x: page.side; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                text: page.results.length + (page.results.length === 1 ? " resultado" : " resultados")
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
            }
        }
        delegate: Item {
            id: d
            required property var modelData
            required property int index
            readonly property var st: page.dl[modelData.id] || { state: "", pct: 0, msg: "" }
            readonly property bool canDownload: modelData.download_url !== ""
            width: lv.width; height: 62
            Rectangle {
                anchors { fill: parent; leftMargin: page.side; rightMargin: page.side; topMargin: 2; bottomMargin: 2 }
                radius: Theme.radius
                color: page.playingIndex === d.index ? Theme.selected : rowMa.containsMouse ? Theme.hover : Theme.cardBg
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; onDoubleClicked: page.play(page.asTracks(), d.index) }
                CoverArt { id: art; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } width: 42; height: 42; decode: 84; source: d.modelData.cover_url }
                Column {
                    anchors { left: art.right; leftMargin: 12; right: actions.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text { width: parent.width; elide: Text.ElideRight; text: d.modelData.title; color: page.playingIndex === d.index ? Theme.accentFg : Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: [d.modelData.artist, d.modelData.album].filter(function (x) { return !!x }).join(" — ")
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [d.modelData.source, d.modelData.license]
                            Rectangle {
                                required property string modelData
                                width: chip.implicitWidth + 12; height: 16; radius: 8
                                color: "transparent"; border.color: Theme.dimFg; border.width: 1; opacity: 0.85
                                Text { id: chip; anchors.centerIn: parent; text: modelData; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 4; font.weight: Font.DemiBold }
                            }
                        }
                        Text {
                            visible: d.st.state === "failed"
                            text: d.st.msg; color: Theme.destructive; font.family: Theme.font; font.pointSize: Theme.fontSize - 3
                        }
                    }
                }
                Row {
                    id: actions
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; horizontalAlignment: Text.AlignRight
                        text: { var s = Math.round(d.modelData.duration_ms / 1000); return s > 0 ? Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2) : "" }
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                    FlatButton { icon: "play"; circular: true; size: 32; onClicked: page.play(page.asTracks(), d.index) }
                    // download / progress / done
                    Item {
                        width: 34; height: 34
                        anchors.verticalCenter: parent.verticalCenter
                        FlatButton {
                            anchors.centerIn: parent
                            visible: d.st.state === "" || d.st.state === "failed"
                            enabled: d.canDownload
                            opacity: d.canDownload ? 1 : 0.35
                            icon: "download"; circular: true; size: 32
                            onClicked: { page.markQueued(d.modelData.id); page.download(d.modelData) }
                        }
                        // progress ring (Canvas), click to cancel
                        Canvas {
                            id: ring
                            anchors.fill: parent
                            visible: d.st.state === "queued" || d.st.state === "downloading"
                            property real p: d.st.pct < 0 ? 0.25 : d.st.pct / 100
                            property real spin: 0
                            onPChanged: requestPaint()
                            onSpinChanged: requestPaint()
                            onVisibleChanged: requestPaint()
                            NumberAnimation on spin { running: ring.visible && d.st.pct < 0; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
                            onPaint: {
                                var c = getContext("2d"); c.reset()
                                var r = width / 2 - 4
                                c.lineWidth = 3; c.lineCap = "round"
                                c.strokeStyle = Theme.hover; c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
                                c.strokeStyle = Theme.accent; c.beginPath()
                                var a0 = -Math.PI / 2 + spin * Math.PI / 180
                                c.arc(width / 2, height / 2, r, a0, a0 + Math.max(0.05, p) * Math.PI * 2); c.stroke()
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.cancel(d.modelData.id) }
                        }
                        Icon { anchors.centerIn: parent; visible: d.st.state === "done"; name: "check"; size: 18; color: Theme.accentFg }
                    }
                }
            }
        }
    }

    Column {
        anchors.centerIn: lv
        visible: page.results.length === 0
        spacing: 10
        Icon { anchors.horizontalCenter: parent.horizontalCenter; visible: !page.searching; name: "download"; size: 72; color: Theme.dimFg; opacity: 0.6 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.searching ? "Buscando…" : page.lastQuery === "" ? "Busque algo para ouvir" : "Nada encontrado"
            color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight
        }
    }
}
