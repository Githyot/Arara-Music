import QtQuick
import QtQuick.Controls
import AraraStyle
import QtQuick.Controls.Basic as QQC

// "Editar informações" (AdwDialog-like form): title, artists, album, numbers,
// year, genre, composer and cover of one song. Local files can get the tags
// written into the file; otherwise the change stays in the library.
Popup {
    id: dlg
    property var track: null
    property var orig: null          // editableJson()
    property string coverPath: ""    // new picture picked, "" = keep
    property bool writeFile: true
    property bool busy: false
    property string error: ""
    signal submit(int trackId, string json, string cover, bool writeFile)
    signal pickCover()
    signal revert(int trackId)

    function start(t, fields, writePref) {
        track = t; orig = fields; coverPath = ""; error = ""; busy = false
        writeFile = writePref
        title.text = fields.title; artist.text = fields.artist
        album.text = fields.album; albumArtist.text = fields.albumArtist
        trackNo.text = fields.trackNo > 0 ? String(fields.trackNo) : ""
        discNo.text = fields.discNo > 0 ? String(fields.discNo) : ""
        year.text = fields.year > 0 ? String(fields.year) : ""
        genre.text = fields.genre; composer.text = fields.composer
        open(); flick.contentY = 0
        title.input.forceActiveFocus(); title.input.selectAll()
    }
    function coverPicked(path) { coverPath = path }
    function finished(res) {
        busy = false
        if (res.error) { error = res.error; return }
        close()
    }
    // Only what changed; numbers as 0 when cleared (the core clears them).
    function changes() {
        var o = orig, c = {}
        function txt(key, field) { var v = field.text.trim(); if (v !== String(o[key] || "")) c[key] = v }
        function num(key, field) { var v = parseInt(field.text, 10); v = isNaN(v) ? 0 : v; if (v !== Number(o[key] || 0)) c[key] = v }
        txt("title", title); txt("artist", artist); txt("album", album)
        // Album artist follows the artist when it was the same and wasn't touched.
        if (albumArtist.text.trim() === String(o.albumArtist || "") && String(o.albumArtist || "") === String(o.artist || "") && c.artist !== undefined)
            c.albumArtist = c.artist
        else txt("albumArtist", albumArtist)
        num("trackNo", trackNo); num("discNo", discNo); num("year", year)
        txt("genre", genre); txt("composer", composer)
        return c
    }
    readonly property bool canSave: !busy && title.text.trim() !== ""
    function accept() {
        if (!canSave || !orig) return
        var c = changes()
        if (Object.keys(c).length === 0 && coverPath === "") { close(); return }
        busy = true; error = ""
        submit(track.id, JSON.stringify(c), coverPath, orig.local && writeFile)
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, parent.width - 24)
    height: Math.min(implicitHeight, parent.height - 24)
    modal: true
    focus: true
    padding: 0
    closePolicy: busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    Overlay.modal: Rectangle { color: "#4d000000" }
    background: Rectangle { radius: Theme.dialogRadius; color: Theme.popupBg; border.color: Theme.border; border.width: Theme.fluent || Theme.apple ? 1 : 0 }

    component Field: Rectangle {
        id: fld
        property alias input: ti
        property alias text: ti.text
        property string label: ""
        property string placeholder: ""
        property bool numeric: false
        property int maxLen: 32767
        height: 52; radius: Theme.radius; color: Theme.hover
        border.color: ti.activeFocus ? Theme.accent : "transparent"; border.width: 2
        Text {
            x: 12; y: 6; text: fld.label
            color: ti.activeFocus ? Theme.accentFg : Theme.dimFg
            font.family: Theme.font; font.pointSize: Theme.fontSize - 2
        }
        TextInput {
            id: ti
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 8 }
            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: "white"
            font.family: Theme.font; font.pointSize: Theme.fontSize
            clip: true
            enabled: !dlg.busy
            activeFocusOnTab: true
            maximumLength: fld.maxLen
            validator: fld.numeric ? digits : null
            inputMethodHints: fld.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
            onAccepted: dlg.accept()
            Text { visible: !ti.text && !ti.activeFocus; text: fld.placeholder; color: Theme.dimFg; font: ti.font }
        }
    }
    RegularExpressionValidator { id: digits; regularExpression: /[0-9]{0,4}/ }

    contentItem: Item {
        implicitHeight: flick.contentHeight + buttons.height
        Flickable {
            QQC.ScrollBar.vertical: OverlayScrollBar {}
            id: flick
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: buttons.top }
            contentHeight: form.height + 48
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: form
                x: 24; y: 24
                width: flick.width - 48
                spacing: 12

                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: "Editar informações"
                    color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight
                }
                Item { width: 1; height: 2 }

                // Cover + the two main fields side by side (stacked when narrow).
                Flow {
                    width: parent.width
                    spacing: 16
                    readonly property bool narrow: width < 420
                    Column {
                        spacing: 8
                        width: 132
                        Item {
                            width: 132; height: 132
                            CoverArt {
                                anchors.fill: parent
                                decode: 264
                                source: dlg.coverPath !== "" ? (dlg.coverPath.indexOf("file:") === 0 ? dlg.coverPath : "file://" + dlg.coverPath) : (dlg.orig ? dlg.orig.cover || "" : "")
                            }
                            Rectangle {
                                anchors.fill: parent; radius: Math.max(3, Math.round(width * Theme.coverRound))
                                color: "#000000"; opacity: cm.containsMouse ? 0.35 : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.ms(120) } }
                            }
                            Icon { anchors.centerIn: parent; name: "edit"; size: 28; color: "white"; visible: cm.containsMouse }
                            MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !dlg.busy; onClicked: dlg.pickCover() }
                        }
                        FlatButton {
                            width: 132; text: "Trocar capa…"; color: Theme.hover
                            onClicked: if (!dlg.busy) dlg.pickCover()
                        }
                    }
                    Column {
                        width: parent.narrow ? parent.width : parent.width - 132 - 16
                        spacing: 12
                        Field { id: title; width: parent.width; label: "Título" }
                        Field { id: artist; width: parent.width; label: "Artista" }
                        Field { id: album; width: parent.width; label: "Álbum"; placeholder: "Sem álbum" }
                    }
                }

                Field { id: albumArtist; width: parent.width; label: "Artista do álbum"; placeholder: "Igual ao artista" }
                Row {
                    width: parent.width
                    spacing: 12
                    Field { id: trackNo; width: (parent.width - 24) / 3; label: "Faixa"; numeric: true }
                    Field { id: discNo; width: (parent.width - 24) / 3; label: "Disco"; numeric: true }
                    Field { id: year; width: (parent.width - 24) / 3; label: "Ano"; numeric: true }
                }
                Field { id: genre; width: parent.width; label: "Gênero" }
                Field { id: composer; width: parent.width; label: "Composição"; placeholder: "Separe nomes com ;" }

                // Where the change goes.
                Rectangle {
                    visible: !!dlg.orig && dlg.orig.local
                    width: parent.width; height: wf.height + 24; radius: Theme.radius
                    color: Theme.cardBg; border.color: Theme.border; border.width: Theme.dark ? 0 : 1
                    Column {
                        id: wf
                        anchors { left: parent.left; right: sw.left; leftMargin: 14; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text { text: "Gravar também no arquivo"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            text: dlg.writeFile ? "As etiquetas da música mudam no arquivo, e outros players também veem."
                                                : "A mudança fica só no Arara Music; o arquivo não é alterado."
                            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5
                        }
                    }
                    Toggle { id: sw; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } checked: dlg.writeFile; onToggled: dlg.writeFile = !dlg.writeFile }
                    MouseArea { anchors.fill: wf; enabled: !dlg.busy; onClicked: dlg.writeFile = !dlg.writeFile }
                }
                Row {
                    visible: !!dlg.orig && !dlg.orig.local
                    width: parent.width; spacing: 8
                    Icon { id: ci; name: "cloud"; size: 16; color: Theme.dimFg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        width: parent.width - ci.width - 8; wrapMode: Text.Wrap
                        text: "Música de servidor: a mudança fica só no Arara Music e continua valendo depois de sincronizar."
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                }
                Row {
                    visible: !!dlg.orig && dlg.orig.overridden
                    width: parent.width; spacing: 8
                    Icon { id: ui; name: "undo"; size: 16; color: Theme.dimFg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        width: parent.width - ui.width - rv.width - 16; wrapMode: Text.Wrap; anchors.verticalCenter: parent.verticalCenter
                        text: "Esta música tem mudanças guardadas só no Arara Music."
                        color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                    }
                    FlatButton { id: rv; text: "Desfazer"; color: Theme.hover; onClicked: if (!dlg.busy) { dlg.revert(dlg.track.id); dlg.close() } }
                }

                Row {
                    visible: dlg.error !== ""
                    width: parent.width; spacing: 8
                    Icon { id: warn; name: "warning"; size: 16; color: Theme.destructive; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: parent.width - warn.width - 8; wrapMode: Text.Wrap; text: dlg.error; color: Theme.destructive; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                }
            }
        }
        Item {
            id: buttons
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 76
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.border; opacity: flick.contentHeight > flick.height ? 0.8 : 0 }
            Row {
                spacing: 12
                anchors.centerIn: parent
                readonly property real bw: Math.min(200, (dlg.width - 48 - 12) / 2)
                FlatButton { text: "Cancelar"; color: Theme.hover; width: parent.bw; opacity: dlg.busy ? 0.5 : 1; onClicked: if (!dlg.busy) dlg.close() }
                FlatButton {
                    text: dlg.busy ? "Salvando…" : "Salvar"; width: parent.bw
                    suggested: true
                    opacity: dlg.canSave ? 1 : 0.5
                    onClicked: dlg.accept()
                }
            }
        }
    }
}
