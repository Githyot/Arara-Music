import QtQuick
import AraraStyle
import QtQuick.Layouts

// Client-side header bar: drag to move, double-click to maximize.
// GNOME centres the title; macOS, Material and Fluent put it on the left.
Rectangle {
    id: bar
    property string title: ""
    property string subtitle: ""
    property bool showControls: true
    property bool allWindowButtons: false
    property bool divider: !Theme.material && !Theme.apple
    property alias leading: leadingRow.data
    property alias trailing: trailingRow.data
    property color background: Theme.headerBg
    property var window: null
    readonly property bool centred: Theme.gnome

    height: Theme.headerHeight
    color: background

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onPressed: if (bar.window) bar.window.startSystemMove()
        onDoubleClicked: if (bar.window) bar.window.visibility === 4 ? bar.window.showNormal() : bar.window.showMaximized()
    }

    RowLayout {
        id: leadingRow
        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 6
    }

    // Title: centred across the bar (GNOME) or right after the leading buttons.
    Item {
        id: titleBox
        readonly property real side: Math.max(leadingRow.width + 6, trailingRow.width + controls.width + 12) + 12
        // A wide search field leaves no room in the middle: the title then sits
        // on the left instead of disappearing.
        readonly property bool mid: bar.centred && bar.width - 2 * side >= titleText.implicitWidth + 8
        x: mid ? side : leadingRow.x + leadingRow.width + (leadingRow.width > 0 ? 10 : (Theme.material ? 16 : 12))
        width: Math.max(0, mid ? bar.width - 2 * side : trailingRow.x - x - 12)
        height: titleText.height + (subText.visible ? subText.height : 0)
        anchors.verticalCenter: parent.verticalCenter
        visible: width > 40 && bar.title !== ""
        Text {
            id: titleText
            width: parent.width
            horizontalAlignment: titleBox.mid ? Text.AlignHCenter : Text.AlignLeft
            text: bar.title
            color: Theme.fg
            font.family: Theme.material ? Theme.displayFont : Theme.font
            font.pointSize: Theme.material ? Theme.fontSize + 4 : Theme.apple ? Theme.fontSize + 2 : Theme.fontSize
            font.weight: Theme.material || Theme.fluent ? Font.Normal : Font.Bold
            elide: Text.ElideRight
        }
        Text {
            id: subText
            anchors.top: titleText.bottom
            width: parent.width
            horizontalAlignment: titleText.horizontalAlignment
            visible: bar.subtitle !== ""
            text: bar.subtitle
            color: Theme.dimFg
            font.family: Theme.font; font.pointSize: Theme.fontSize - 2
            elide: Text.ElideRight
        }
    }

    RowLayout {
        id: trailingRow
        anchors { right: controls.left; rightMargin: controls.width > 0 ? 6 : 6; verticalCenter: parent.verticalCenter }
        spacing: 6
    }

    WindowControls {
        id: controls
        visible: bar.showControls && bar.window !== null && !Theme.apple
        width: visible ? implicitWidth : 0
        all: bar.allWindowButtons
        window: bar.window
        anchors { right: parent.right; rightMargin: Theme.fluent ? 0 : 6; top: Theme.fluent ? parent.top : undefined; verticalCenter: Theme.fluent ? undefined : parent.verticalCenter }
    }

    Rectangle { visible: bar.divider; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border; opacity: 0.6 }
}
