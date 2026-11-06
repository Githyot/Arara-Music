import QtQuick
import AraraStyle

// "E" for explicit tracks, like Apple Music: a small filled rounded square
// with the letter in the background colour.
// kind: 1 = marked explicit (tag, server or the user), 2 = only the lyrics
// look explicit (shown when the preference allows), 0 = nothing.
Rectangle {
    id: badge
    property var track: null
    property color fill: Theme.dimFg
    property color ink: Theme.cardBg
    property real size: 15
    readonly property int kind: {
        var o = Prefs.explicitOverride, id = track ? Number(track.id) : -1
        if (o[id] !== undefined) return o[id]
        return track && track.explicit ? Number(track.explicit) : 0
    }
    visible: Prefs.showExplicit && (kind === 1 || (kind === 2 && Prefs.explicitLyrics))
    width: size; height: size
    radius: Math.round(size * 0.22)
    color: fill
    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 0.5
        text: "E"
        color: badge.ink
        font.family: Theme.font
        font.pixelSize: Math.round(badge.size * 0.72)
        font.weight: Font.Bold
    }
}
