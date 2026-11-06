import QtQuick
import QtQuick.Controls
import AraraStyle

// AdwDialog-like form to connect a Subsonic/Navidrome or Jellyfin server.
// Only a derived token is stored; the password never touches the disk.
Popup {
    id: dlg
    property string kind: "subsonic"
    property bool busy: false
    property string error: ""
    signal submit(string kind, string url, string user, string password)

    function start() {
        busy = false; error = ""; url.text = ""; user.text = ""; pass.text = ""
        open(); url.input.forceActiveFocus()
    }
    function finished(ok, message) {
        busy = false
        if (ok) close(); else error = message
    }
    function accept() {
        if (busy || url.text.trim() === "" || user.text.trim() === "") return
        busy = true; error = ""
        submit(kind, url.text.trim(), user.text.trim(), pass.text)
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(420, parent.width - 24)
    modal: true
    focus: true
    padding: 24
    closePolicy: busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    Overlay.modal: Rectangle { color: "#4d000000" }
    background: Rectangle { radius: Theme.dialogRadius; color: Theme.popupBg; border.color: Theme.border; border.width: Theme.fluent || Theme.apple ? 1 : 0 }

    component Field: Rectangle {
        property alias input: ti
        property alias text: ti.text
        property string label: ""
        property string placeholder: ""
        property bool secret: false
        width: parent.width; height: 52; radius: Theme.radius; color: Theme.hover
        border.color: ti.activeFocus ? Theme.accent : "transparent"; border.width: 2
        Text {
            x: 12; y: 6; text: parent.label
            color: ti.activeFocus ? Theme.accentFg : Theme.dimFg
            font.family: Theme.font; font.pointSize: Theme.fontSize - 2
        }
        TextInput {
            id: ti
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 8 }
            color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: "white"
            font.family: Theme.font; font.pointSize: Theme.fontSize
            echoMode: parent.secret ? TextInput.Password : TextInput.Normal
            enabled: !dlg.busy
            activeFocusOnTab: true
            onAccepted: dlg.accept()
            Text { visible: !ti.text && !ti.activeFocus; text: parent.parent.placeholder; color: Theme.dimFg; font: ti.font }
        }
    }

    contentItem: Column {
        spacing: 12
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "server"; size: 48; color: Theme.dimFg }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Adicionar servidor"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "O catálogo fica guardado neste computador: abre na hora e dá para navegar mesmo offline."
            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
        }

        // AdwToggleGroup-like kind switcher
        Rectangle {
            id: sw
            width: parent.width; height: 36; radius: Theme.radius; color: Theme.hover
            Row {
                anchors.fill: parent; anchors.margins: 3
                Repeater {
                    model: [{ k: "subsonic", t: "Navidrome / Subsonic" }, { k: "jellyfin", t: "Jellyfin" }]
                    Rectangle {
                        required property var modelData
                        width: (sw.width - 6) / 2; height: sw.height - 6; radius: Theme.radius - 2
                        color: dlg.kind === modelData.k ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.15) : "#ffffff") : "transparent"
                        Text { anchors.centerIn: parent; text: modelData.t; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; enabled: !dlg.busy; onClicked: dlg.kind = modelData.k }
                    }
                }
            }
        }

        Field { id: url; label: "Endereço"; placeholder: dlg.kind === "jellyfin" ? "https://jellyfin.exemplo.com" : "https://musica.exemplo.com" }
        Field { id: user; label: "Usuário" }
        Field { id: pass; label: "Senha"; secret: true }

        Row {
            visible: dlg.error !== ""
            width: parent.width; spacing: 8
            Icon { id: warn; name: "warning"; size: 16; color: Theme.destructive; anchors.verticalCenter: parent.verticalCenter }
            Text { width: parent.width - warn.width - 8; wrapMode: Text.Wrap; text: dlg.error; color: Theme.destructive; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
        }

        Item { width: 1; height: 4 }
        Row {
            spacing: 12
            anchors.horizontalCenter: parent.horizontalCenter
            FlatButton { text: "Cancelar"; color: Theme.hover; width: 170; opacity: dlg.busy ? 0.5 : 1; onClicked: if (!dlg.busy) dlg.close() }
            FlatButton {
                text: dlg.busy ? "Conectando…" : "Conectar"; width: 170
                suggested: true
                opacity: url.text.trim() !== "" && user.text.trim() !== "" ? 1 : 0.5
                onClicked: dlg.accept()
            }
        }
    }
}
