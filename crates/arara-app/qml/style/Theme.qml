pragma Singleton
import QtQuick

// libadwaita palette and metrics (GNOME HIG), so the Qt UI sits naturally
// next to GNOME apps. Values follow libadwaita 1.6 named colors.
QtObject {
    property bool dark: false

    // System accent (GNOME 47+ via the settings portal); blue by default.
    property color accent: "#3584e4"
    // Accent used for text/icons: lighter on dark, darker on light, like libadwaita.
    readonly property color accentFg: dark ? Qt.lighter(accent, 1.45) : Qt.darker(accent, 1.12)
    readonly property color destructive: dark ? "#ff7b63" : "#c01c28"

    readonly property color windowBg: dark ? "#222226" : "#fafafb"
    readonly property color viewBg: dark ? "#1d1d20" : "#ffffff"
    readonly property color headerBg: dark ? "#2e2e32" : "#ffffff"
    readonly property color sidebarBg: dark ? "#2e2e32" : "#ebebed"
    readonly property color cardBg: dark ? Qt.rgba(1, 1, 1, 0.08) : "#ffffff"
    readonly property color fg: dark ? "#ffffff" : Qt.rgba(0, 0, 6/255, 0.8)
    readonly property color dimFg: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 6/255, 0.5)
    readonly property color border: dark ? Qt.rgba(0, 0, 0, 0.36) : Qt.rgba(0, 0, 6/255, 0.15)
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 6/255, 0.06)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 6/255, 0.13)
    readonly property color selected: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 6/255, 0.10)

    readonly property int headerHeight: 47
    readonly property int radius: 6
    readonly property int cardRadius: 12
    readonly property int windowRadius: 12
    readonly property int spacing: 12

    readonly property string font: "Adwaita Sans, Cantarell, Inter, sans-serif"
    readonly property int fontSize: 11 // pt, GNOME default

    // Symbolic icons: use the system icon theme (Adwaita) via image://theme when
    // available, with unicode fallbacks for environments without it.
    function glyph(name) {
        return ({ "play": "▶", "pause": "⏸", "next": "⏭", "prev": "⏮",
                  "search": "⌕", "close": "✕", "back": "‹", "lyrics": "♪",
                  "menu": "☰", "min": "–", "max": "□", "shuffle": "⇄",
                  "repeat": "↻", "repeat1": "↻¹", "star": "★", "unstar": "☆",
                  "more": "⋮", "queue": "≡", "add": "+", "artist": "☺", "recent": "◷",
                  "playlist": "☰", "volume": "♫", "trash": "✕" })[name] || "?"
    }
}
