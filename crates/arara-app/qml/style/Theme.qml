pragma Singleton
import QtQuick

// One set of design tokens, four looks. `style` picks the platform language:
//   gnome    libadwaita 1.6 (the default, follows the GNOME HIG)
//   apple    macOS 26 / Apple Music: floating sidebar, accent-tinted icons, small radii
//   material Material 3 / Android: tonal surfaces from the accent, pill navigation
//   fluent   Windows 11 / Fluent 2: Mica window, layered content, accent indicator
// Every component reads only these tokens, so switching is instant and cohesive.
QtObject {
    id: t
    property string style: "gnome"
    property bool dark: false

    readonly property bool gnome: style === "gnome"
    readonly property bool apple: style === "apple"
    readonly property bool material: style === "material"
    readonly property bool fluent: style === "fluent"

    // ---------- colour ----------
    // The accent is chosen by Main (theme default, system, cover or custom).
    property color accent: styleAccent
    readonly property color styleAccent: apple ? "#fa2d48"
        : material ? (dark ? "#d0bcff" : "#6750a4")
        : fluent ? (dark ? "#60cdff" : "#005fb8")
        : "#3584e4"
    // Text/icons drawn in the accent colour stay readable on the window background.
    readonly property color accentFg: material || fluent ? accent
        : dark ? Qt.lighter(accent, 1.45) : Qt.darker(accent, 1.12)
    // Ink on top of an accent fill; set by Main from the final accent.
    property color accentInk: "#ffffff"
    readonly property color destructive: dark ? "#ff7b63" : "#c01c28"

    function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function mix(a, b, k) { return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1) }
    function pick(gn, ap, ma, fl) { return apple ? ap : material ? ma : fluent ? fl : gn }

    // Material You derives its surfaces from the accent; the others are neutral.
    readonly property color _m0: dark ? "#141218" : "#fef7ff"
    function tone(k) { return mix(_m0, accent, k) }

    readonly property color windowBg: pick(dark ? "#222226" : "#fafafb",
                                           dark ? "#1e1e1e" : "#ffffff",
                                           tone(dark ? 0.05 : 0.03),
                                           dark ? "#202020" : "#f3f3f3")
    readonly property color viewBg: pick(dark ? "#1d1d20" : "#ffffff",
                                         dark ? "#1e1e1e" : "#ffffff",
                                         tone(dark ? 0.05 : 0.03),
                                         dark ? "#272727" : "#f9f9f9")
    readonly property color headerBg: pick(dark ? "#2e2e32" : "#ffffff",
                                           dark ? "#1e1e1e" : "#ffffff",
                                           tone(dark ? 0.05 : 0.03),
                                           dark ? "#272727" : "#f9f9f9")
    readonly property color sidebarBg: pick(dark ? "#2e2e32" : "#ebebed",
                                            dark ? "#2c2c2e" : "#f0f0f2",
                                            tone(dark ? 0.09 : 0.07),
                                            dark ? "#202020" : "#f3f3f3")
    // Opaque, so overlapping card pieces never add up into stripes.
    readonly property color cardBg: pick(dark ? "#343437" : "#ffffff",
                                         dark ? "#2c2c2e" : "#ffffff",
                                         tone(dark ? 0.11 : 0.08),
                                         dark ? "#2d2d2d" : "#ffffff")
    readonly property color popupBg: pick(dark ? "#36363a" : "#ffffff",
                                          dark ? "#323234" : "#fbfbfd",
                                          tone(dark ? 0.13 : 0.06),
                                          dark ? "#2c2c2c" : "#f9f9f9")
    readonly property color fg: pick(dark ? "#ffffff" : Qt.rgba(0, 0, 6/255, 0.8),
                                     dark ? "#f5f5f7" : "#1d1d1f",
                                     dark ? "#e6e0e9" : "#1d1b20",
                                     dark ? "#ffffff" : "#1b1b1b")
    readonly property color dimFg: pick(dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 6/255, 0.5),
                                        dark ? Qt.rgba(235/255, 235/255, 245/255, 0.6) : Qt.rgba(60/255, 60/255, 67/255, 0.6),
                                        dark ? "#cac4d0" : "#49454f",
                                        dark ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.6))
    readonly property color border: pick(dark ? Qt.rgba(0, 0, 0, 0.36) : Qt.rgba(0, 0, 6/255, 0.15),
                                         dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.1),
                                         dark ? "#49454f" : "#cac4d0",
                                         dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08))
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, material ? 0.08 : 0.07) : Qt.rgba(0, 0, 6/255, material ? 0.08 : 0.05)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 6/255, 0.11)
    readonly property color selected: material ? mix(_m0, accent, dark ? 0.32 : 0.2)
        : dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 6/255, apple ? 0.07 : 0.09)
    // Search box / text field fill.
    readonly property color fieldBg: pick(hover,
                                          dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05),
                                          tone(dark ? 0.16 : 0.12),
                                          dark ? Qt.rgba(1, 1, 1, 0.06) : "#ffffff")
    readonly property color toastBg: material ? (dark ? "#e6e0e9" : "#322f35") : dark ? "#e6e6e6" : "#2e2e32"
    readonly property color toastFg: material ? (dark ? "#322f35" : "#f5eff7") : dark ? "#1d1d20" : "#ffffff"

    // ---------- shape ----------
    readonly property int radius: pick(6, 6, 20, 4)          // buttons, rows, fields
    readonly property bool pillButtons: material             // icon buttons are circles, rows are pills
    readonly property int cardRadius: pick(12, 10, 16, 8)
    readonly property int popupRadius: pick(12, 10, 4, 8)
    readonly property int dialogRadius: pick(18, 14, 28, 8)
    readonly property int windowRadius: pick(12, 14, 16, 8)
    readonly property real coverRound: pick(0.07, 0.045, 0.1, 0.05) // share of the cover width
    readonly property int toastRadius: pick(20, 20, 4, 8)

    // ---------- layout ----------
    readonly property int headerHeight: pick(47, 52, 60, 48)
    readonly property int rowHeight: Math.round(pick(38, 30, 46, 36) * (compact ? 0.86 : 1))
    readonly property int sidebarWidth: pick(230, 220, 250, 240)
    readonly property int spacing: 12
    property bool compact: false
    // Smallest album tile; the grid adds columns as the window grows.
    property int tileMin: 160

    // ---------- type ----------
    // Each look asks for its platform font and falls back to Inter (then the system).
    readonly property var _families: Qt.fontFamilies()
    function firstFont(list) {
        for (var i = 0; i < list.length; i++) if (_families.indexOf(list[i]) >= 0) return list[i]
        return list[list.length - 1]
    }
    readonly property string font: pick(firstFont(["Adwaita Sans", "Cantarell", "Inter", "Noto Sans", "sans-serif"]),
                                        firstFont(["SF Pro Text", "SF Pro", "Inter", "Helvetica Neue", "sans-serif"]),
                                        firstFont(["Roboto Flex", "Roboto", "Google Sans Text", "Noto Sans", "Inter", "sans-serif"]),
                                        firstFont(["Segoe UI Variable Text", "Segoe UI", "Selawik", "Noto Sans", "Inter", "sans-serif"]))
    readonly property string displayFont: pick(font, firstFont(["SF Pro Display", "Inter Display", "Inter", "sans-serif"]),
                                               firstFont(["Google Sans", "Roboto", "Noto Sans", "Inter", "sans-serif"]), font)
    property real fontScale: 1.0
    readonly property real fontSize: pick(11, 10, 11, 10.5) * fontScale // pt
    readonly property real titleSize: pick(20, 22, 22, 20) * fontScale
    readonly property real headingSize: pick(15, 14, 18, 15) * fontScale
    readonly property int titleWeight: pick(Font.Bold, Font.Bold, Font.Normal, Font.DemiBold)
    readonly property int headingWeight: pick(Font.Bold, Font.DemiBold, Font.Normal, Font.DemiBold)
    // Sidebar section labels.
    readonly property real sectionSize: pick(fontSize - 1, fontSize - 1, fontSize - 0.5, fontSize)
    readonly property int sectionWeight: pick(Font.Bold, Font.DemiBold, Font.Medium, Font.DemiBold)
    readonly property bool sectionDim: !fluent

    // ---------- motion ----------
    property bool reduceMotion: false
    function ms(d) { return reduceMotion ? 0 : d }

    // Icons: see Icon.qml (bundled Adwaita symbolic SVGs, tinted by a shader).
}
