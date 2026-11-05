import QtQuick
import AraraStyle
import QtQuick.Layouts

// Client-side header bar like AdwHeaderBar: drag to move, double-click to
// maximize, window controls on the right (GNOME default layout: close only).
Rectangle {
    id: bar
    property string title: ""
    property string subtitle: ""
    property bool showControls: true
    property alias leading: leadingRow.data
    property alias trailing: trailingRow.data
    property color background: Theme.headerBg
    property var window: null

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

    Column {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, bar.width - leadingRow.width - trailingRow.width - 120)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: bar.title
            color: Theme.fg
            font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.Bold
            elide: Text.ElideRight
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: bar.subtitle !== ""
            text: bar.subtitle
            color: Theme.dimFg
            font.family: Theme.font; font.pointSize: Theme.fontSize - 2
            elide: Text.ElideRight
        }
    }

    RowLayout {
        id: trailingRow
        anchors { right: controls.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
        spacing: 6
    }

    Row {
        id: controls
        visible: bar.showControls && bar.window !== null
        width: visible ? implicitWidth : 0
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        FlatButton {
            icon: "close"; circular: true; size: 24
            color: hovered ? Theme.pressed : Theme.hover
            onClicked: bar.window.close()
        }
    }

    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border; opacity: 0.6 }
}
