import QtQuick
import QtQuick.Controls.Basic

// Overlay scroll bar in the style of the current theme (libadwaita by
// default): a thin pill over the content that shows up while the view moves
// or the mouse is near, and widens under the pointer so it is easy to grab.
// Attach with `QQC.ScrollBar.vertical: OverlayScrollBar {}`.
ScrollBar {
    id: sb
    // Views that scroll by themselves (karaoke lyrics): only show the bar for
    // the user's own scrolling, not for every automatic move.
    property bool userOnly: false
    // On a dark or tinted background (player panel, lyrics) regardless of theme.
    property bool onDark: false
    readonly property var view: parent
    readonly property bool userMoving: !!view && ((view.dragging === true) || (view.flicking === true))
    readonly property bool shown: size < 1 && (hovered || pressed || (userOnly ? userMoving : active))
    readonly property bool wide: hovered || pressed

    policy: ScrollBar.AsNeeded
    minimumSize: 0.05
    padding: Theme.fluent ? 2 : 3
    // Only take mouse input where the thumb is; the content stays clickable.
    hoverEnabled: true

    // Thickness per theme: idle / under the pointer.
    readonly property real thin: Theme.pick(3, 5, 4, 2)
    readonly property real thick: Theme.pick(8, 9, 8, 6)
    readonly property color ink: onDark || Theme.dark ? "#ffffff" : "#000006"

    contentItem: Rectangle {
        implicitWidth: sb.wide ? sb.thick : sb.thin
        implicitHeight: implicitWidth
        radius: width / 2
        color: sb.ink
        opacity: sb.shown ? (sb.pressed ? 0.6 : sb.wide ? 0.45 : 0.32) : 0
        Behavior on opacity { NumberAnimation { duration: sb.shown ? 120 : 500 } }
        Behavior on implicitWidth { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    // A faint track only while the pointer is on the bar (GNOME/Fluent do this).
    background: Rectangle {
        implicitWidth: sb.thick + sb.padding * 2
        radius: Theme.material ? 0 : width / 2
        color: sb.ink
        opacity: sb.wide && !Theme.apple ? 0.06 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
}
