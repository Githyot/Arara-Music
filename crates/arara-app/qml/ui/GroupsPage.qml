import QtQuick
import AraraStyle

// A category listing (genres, years, composers, folders) as a boxed list,
// with the same fast scroll and A–Z index as the song list.
Item {
    id: page
    property string kind: "genre"
    property var groups: []
    signal open(var group)

    readonly property string title: kind === "genre" ? "Gêneros" : kind === "year" ? "Anos" : kind === "composer" ? "Compositores" : "Pastas"
    readonly property string icon: kind === "genre" ? "genre" : kind === "year" ? "year" : kind === "composer" ? "composer" : "folder"
    // Years are indexed by decade, everything else by first letter.
    function labelOf(g) { return kind === "year" ? String(Math.floor(Number(g.name) / 10) * 10) : g.l }
    readonly property var sections: {
        var out = [], last = ""
        for (var i = 0; i < groups.length; i++) {
            var l = labelOf(groups[i])
            if (l !== last) { out.push({ l: l, row: i }); last = l }
        }
        return out
    }
    readonly property int side: Math.max(24, (width - 900) / 2)
    readonly property int rightSide: Math.max(side, fast.width + 16)

    ListView {
        id: lv
        anchors.fill: parent
        clip: true
        model: page.groups
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: 18
        header: Item {
            width: lv.width; height: 52
            Text {
                x: page.side; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                text: page.title + " · " + page.groups.length
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold
            }
        }
        delegate: Item {
            id: d
            required property var modelData
            required property int index
            width: lv.width; height: 58
            readonly property bool first: index === 0
            readonly property bool last: index === page.groups.length - 1
            Rectangle {
                anchors { fill: parent; leftMargin: page.side; rightMargin: page.rightSide }
                color: ma.containsMouse ? Qt.tint(Theme.cardBg, Theme.hover) : Theme.cardBg
                radius: d.first || d.last ? Theme.cardRadius : 0
                Rectangle { visible: d.first && !d.last; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: Theme.cardRadius; color: parent.color }
                Rectangle { visible: d.last && !d.first; anchors { left: parent.left; right: parent.right; top: parent.top } height: Theme.cardRadius; color: parent.color }
                CoverArt {
                    id: art
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 40; height: 40; radius: 6; decode: 80
                    source: d.modelData.cover
                }
                Column {
                    anchors { left: art.right; leftMargin: 12; right: arrow.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    Text { width: parent.width; elide: Text.ElideRight; text: d.modelData.name; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize }
                    Text { width: parent.width; elide: Text.ElideMiddle; text: d.modelData.detail; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                }
                Icon { id: arrow; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } name: "back"; size: 16; color: Theme.dimFg; rotation: 180 }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border; opacity: 0.5; visible: !d.last }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.open(d.modelData) }
            }
        }
    }
    FastScroll {
        id: fast
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 4; topMargin: 52 }
        view: lv
        sections: page.sections
        labelAt: function (i) { return page.groups[i] ? page.labelOf(page.groups[i]) : "" }
    }
    Column {
        anchors.centerIn: parent
        visible: page.groups.length === 0
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: page.icon; size: 96; color: Theme.dimFg }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Nada por aqui ainda"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize + 1; font.weight: Theme.headingWeight }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.kind === "composer" ? "Os compositores vêm das tags das músicas." : page.kind === "genre" ? "Os gêneros vêm das tags das músicas." : ""
            color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize
        }
    }
}
