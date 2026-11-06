import QtQuick

// Window buttons in the platform's own shape and place:
//   GNOME   round grey buttons, right (close only by default)
//   Apple   traffic lights, left (the caller puts them on the left)
//   Material plain icons, right
//   Fluent  wide caption buttons flush with the top-right corner, red close
Row {
    id: wc
    property var window: null
    property bool onDark: false
    property bool all: false          // minimize + maximize too
    readonly property bool maximized: window && window.visibility === 4
    readonly property color ink: onDark ? "white" : Theme.fg
    spacing: Theme.apple ? 8 : Theme.fluent ? 0 : 6

    readonly property var buttons: Theme.apple ? ["close", "minimize", "maximize"]
        : all ? ["minimize", "maximize", "close"] : ["close"]

    function act(b) {
        if (!window) return
        if (b === "close") window.close()
        else if (b === "minimize") window.showMinimized()
        else maximized ? window.showNormal() : window.showMaximized()
    }

    Repeater {
        model: wc.buttons
        Item {
            id: btn
            required property string modelData
            width: Theme.apple ? 12 : Theme.fluent ? 46 : Theme.material ? 32 : 24
            height: Theme.apple ? 12 : Theme.fluent ? 32 : Theme.material ? 32 : 24
            anchors.verticalCenter: Theme.fluent ? undefined : parent.verticalCenter
            readonly property bool hot: m.containsMouse
            // macOS: coloured dots, glyphs show when the group is hovered
            Rectangle {
                visible: Theme.apple
                anchors.fill: parent; radius: width / 2
                color: btn.modelData === "close" ? "#ff5f57" : btn.modelData === "minimize" ? "#febc2e" : "#28c840"
                border.width: 0.5; border.color: Qt.rgba(0, 0, 0, 0.12)
            }
            Rectangle {
                visible: !Theme.apple
                anchors.fill: parent
                radius: Theme.fluent ? 0 : width / 2
                color: Theme.fluent ? (btn.hot ? (btn.modelData === "close" ? "#c42b1c" : (wc.onDark ? Qt.rgba(1, 1, 1, 0.1) : Theme.hover)) : "transparent")
                     : Theme.material ? (btn.hot ? (wc.onDark ? Qt.rgba(1, 1, 1, 0.14) : Theme.hover) : "transparent")
                     : (wc.onDark ? Qt.rgba(1, 1, 1, btn.hot ? 0.25 : 0.12) : (btn.hot ? Theme.pressed : Theme.hover))
            }
            Icon {
                anchors.centerIn: parent
                visible: !Theme.apple || hoverAll.hovered
                size: Theme.apple ? 8 : 16
                name: btn.modelData === "maximize" && wc.maximized ? "restore" : btn.modelData
                color: Theme.apple ? Qt.rgba(0, 0, 0, 0.6) : (Theme.fluent && btn.hot && btn.modelData === "close") ? "white" : wc.ink
            }
            MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: wc.act(btn.modelData) }
        }
    }
    HoverHandler { id: hoverAll }
}
