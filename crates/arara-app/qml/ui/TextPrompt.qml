import QtQuick
import QtQuick.Controls
import AraraStyle

// AdwAlertDialog-like prompt with one text field.
Popup {
    id: dlg
    property string heading: ""
    property string body: ""
    property string acceptLabel: "Criar"
    property bool destructive: false
    property bool needsText: true
    property bool infoOnly: false
    property var onAccept: null
    property alias text: field.text

    function ask(h, b, initial, label, cb) {
        heading = h; body = b; field.text = initial; acceptLabel = label; onAccept = cb
        destructive = false; needsText = true; infoOnly = false
        open(); field.forceActiveFocus(); field.selectAll()
    }
    function confirm(h, b, label, cb) {
        heading = h; body = b; acceptLabel = label; onAccept = cb
        destructive = true; needsText = false; infoOnly = false
        open()
    }
    // Message with a single "Fechar" button (about, shortcuts, import report).
    function info(h, b, label, cb) {
        heading = h; body = b; acceptLabel = label || ""; onAccept = cb || null
        destructive = false; needsText = false; infoOnly = true
        open()
    }
    function accept() {
        if (needsText && field.text.trim() === "") return
        var cb = onAccept; close(); if (cb) cb(field.text.trim())
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(372, parent.width - 24)
    modal: true
    focus: true
    padding: 24
    Overlay.modal: Rectangle { color: "#4d000000" }
    background: Rectangle { radius: 18; color: Theme.dark ? "#36363a" : "#ffffff" }

    contentItem: Column {
        spacing: 12
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: dlg.heading; color: Theme.fg; font.family: Theme.font; font.pointSize: 15; font.weight: Font.Bold }
        Text { visible: text !== ""; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: dlg.body; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize }
        Rectangle {
            visible: dlg.needsText
            width: parent.width; height: 38; radius: Theme.radius; color: Theme.hover
            border.color: field.activeFocus ? Theme.accent : "transparent"; border.width: 2
            TextInput {
                id: field
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: "white"
                font.family: Theme.font; font.pointSize: Theme.fontSize
                onAccepted: dlg.accept()
            }
        }
        Item { width: 1; height: 4 }
        Row {
            spacing: 12
            anchors.horizontalCenter: parent.horizontalCenter
            FlatButton { text: dlg.infoOnly ? "Fechar" : "Cancelar"; color: Theme.hover; width: 150; onClicked: dlg.close() }
            FlatButton {
                visible: !dlg.infoOnly || dlg.acceptLabel !== ""
                text: dlg.acceptLabel; width: 150
                suggested: !dlg.destructive
                destructive: dlg.destructive
                onClicked: dlg.accept()
            }
        }
    }
}
