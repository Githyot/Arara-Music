import QtQuick
import AraraStyle

// A titled, boxed list (AdwPreferencesGroup look) for the info pages.
// mode "kv": rows are {k, v, link?}; mode "people": rows are {name, role, photo?}.
Column {
    id: sec
    property string title: ""
    property string note: ""
    property var rows: []
    property string mode: "kv"
    property bool busy: false
    property string busyText: ""
    signal activated(var row)
    spacing: 8
    visible: rows.length > 0 || busy

    function initials(n) {
        var p = String(n || "").replace(/[()\[\]{}.,;:!?"'&+\-\/]/g, " ").trim().split(/\s+/)
        return ((p[0] || "?")[0] + (p.length > 1 ? p[p.length - 1][0] : "")).toUpperCase()
    }
    // Stable soft colour per name for the initials avatar.
    function tint(n) {
        var h = 0, s = String(n || "")
        for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360
        return Qt.hsla(h / 360, 0.45, Theme.dark ? 0.42 : 0.62, 1)
    }

    Text {
        visible: sec.title !== ""
        leftPadding: 4
        text: sec.title
        color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize + 0.5; font.weight: Theme.headingWeight
    }
    Rectangle {
        width: sec.width
        height: box.height
        radius: Theme.cardRadius
        color: Theme.cardBg
        border.color: Theme.border; border.width: Theme.dark ? 0 : 1
        clip: true
        Column {
            id: box
            width: parent.width
            Repeater {
                model: sec.rows
                Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool people: sec.mode === "people"
                    readonly property bool clickable: !!modelData.link || people && !!modelData.inLibrary
                    width: box.width
                    height: people ? 58 : Math.max(44, kv.implicitHeight + 22)
                    color: ma.containsMouse && clickable ? Theme.hover : "transparent"
                    Rectangle {
                        visible: row.index > 0
                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: row.people ? 64 : 14 }
                        height: 1; color: Theme.border; opacity: 0.6
                    }
                    // People: avatar + name + role.
                    Rectangle {
                        id: avatar
                        visible: row.people
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 38; height: 38; radius: 19
                        color: sec.tint(row.modelData.name)
                        Text { anchors.centerIn: parent; text: sec.initials(row.modelData.name); color: "#ffffff"; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                    }
                    Column {
                        visible: row.people
                        anchors { left: avatar.right; leftMargin: 12; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.name || ""; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize + 0.5 }
                        Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.role || ""; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 0.5 }
                    }
                    // Key/value.
                    Item {
                        id: kv
                        visible: !row.people
                        anchors { left: parent.left; leftMargin: 14; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        implicitHeight: Math.max(kText.implicitHeight, vText.implicitHeight)
                        Text {
                            id: kText
                            width: Math.min(150, parent.width * 0.4)
                            text: row.modelData.k || ""; color: Theme.dimFg; wrapMode: Text.Wrap
                            font.family: Theme.font; font.pointSize: Theme.fontSize
                        }
                        Text {
                            id: vText
                            anchors { left: kText.right; leftMargin: 12; right: parent.right }
                            horizontalAlignment: Text.AlignRight
                            text: row.modelData.v === undefined || row.modelData.v === null ? "" : String(row.modelData.v)
                            color: row.modelData.link ? Theme.accentFg : Theme.fg
                            wrapMode: Text.WrapAnywhere; maximumLineCount: 4; elide: Text.ElideRight
                            font.family: Theme.font; font.pointSize: Theme.fontSize
                        }
                    }
                    Icon {
                        id: chev
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        name: "go-next"; size: 14; color: Theme.dimFg
                        visible: row.clickable
                        width: visible ? 14 : 0
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.clickable
                        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: sec.activated(row.modelData)
                    }
                }
            }
            // Online lookup in progress.
            Item {
                visible: sec.busy
                width: box.width; height: 44
                Rectangle { visible: sec.rows.length > 0; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14 } height: 1; color: Theme.border; opacity: 0.6 }
                Row {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Item {
                        width: 16; height: 16
                        Rectangle {
                            anchors.fill: parent; radius: 8; color: "transparent"
                            border.width: 2; border.color: Theme.dimFg; opacity: 0.35
                        }
                        Rectangle {
                            width: 6; height: 6; radius: 3; color: Theme.accentFg
                            x: 5 + 6 * Math.cos(spin.a); y: 5 + 6 * Math.sin(spin.a)
                        }
                        QtObject { id: spin; property real a: 0 }
                        NumberAnimation { target: spin; property: "a"; from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite; running: sec.busy && sec.visible }
                    }
                    Text { text: sec.busyText; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                }
            }
        }
    }
    Text {
        visible: sec.note !== ""
        width: sec.width
        leftPadding: 4
        wrapMode: Text.Wrap
        text: sec.note; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5
    }
}
