import QtQuick
import QtQuick.Controls
import AraraStyle

// Small popover listing choices with a check on the current one.
Popup {
    id: menu
    property var options: []      // [{k, t}]
    property string current: ""
    signal chosen(string key)
    width: 240
    padding: 6
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    function openUnder(item) {
        var p = item.mapToItem(Overlay.overlay, item.width, item.height + 4)
        x = 0; y = 0
        parent = Overlay.overlay
        x = Math.max(8, p.x - width); y = p.y
        open()
    }
    background: Rectangle { radius: Theme.popupRadius; color: Theme.popupBg; border.color: Theme.border }
    contentItem: Column {
        Repeater {
            model: menu.options
            Rectangle {
                required property var modelData
                width: menu.width - 12; height: 34; radius: Theme.material ? 0 : Theme.radius
                color: ma.containsMouse ? Theme.hover : "transparent"
                Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: modelData.t; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                Icon { visible: menu.current === modelData.k; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } name: "check"; size: 16 }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: { menu.close(); menu.chosen(modelData.k) } }
            }
        }
    }
}
