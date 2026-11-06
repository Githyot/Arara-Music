import QtQuick
import QtQuick.Controls
import AraraStyle

// "Pastas de música": every folder the library is built from, with add/remove.
Popup {
    id: dlg
    property var dirs: []
    signal addRequested()
    signal removeRequested(string dir)

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, parent.width - 24)
    modal: true
    focus: true
    padding: 24
    Overlay.modal: Rectangle { color: "#4d000000" }
    background: Rectangle { radius: Theme.dialogRadius; color: Theme.popupBg; border.color: Theme.border; border.width: Theme.fluent || Theme.apple ? 1 : 0 }

    contentItem: Column {
        spacing: 12
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "folder-music"; size: 44; color: Theme.dimFg }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Pastas de música"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "Todas as pastas entram na mesma biblioteca e são vigiadas: músicas novas aparecem sozinhas."
            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
        }
        Rectangle {
            width: parent.width; height: list.height; radius: Theme.cardRadius; color: Theme.cardBg
            border.color: Theme.border
            Column {
                id: list
                width: parent.width
                Repeater {
                    model: dlg.dirs
                    Item {
                        required property string modelData
                        required property int index
                        width: list.width; height: 50
                        Icon { id: fi; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } name: "folder"; size: 16 }
                        Text {
                            anchors { left: fi.right; leftMargin: 12; right: rm.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: modelData; elide: Text.ElideMiddle
                            color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize
                        }
                        FlatButton {
                            id: rm
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            visible: dlg.dirs.length > 1
                            icon: "trash"; circular: true; size: 30
                            onClicked: dlg.removeRequested(modelData)
                        }
                        Rectangle { visible: index > 0; anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.border; opacity: 0.5 }
                    }
                }
            }
        }
        Row {
            spacing: 10
            anchors.horizontalCenter: parent.horizontalCenter
            FlatButton { text: "Fechar"; color: Theme.hover; width: 140; onClicked: dlg.close() }
            FlatButton { text: "Adicionar pasta…"; suggested: true; width: 170; onClicked: dlg.addRequested() }
        }
    }
}
