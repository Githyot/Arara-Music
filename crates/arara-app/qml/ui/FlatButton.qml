import QtQuick
import AraraStyle
import QtQuick.Controls.Basic as C

// Adwaita "flat" button: transparent until hovered; `suggested` gives the blue pill.
Rectangle {
    id: root
    property string icon: ""
    property string text: ""
    property bool suggested: false
    property bool destructive: false
    property bool circular: false
    property bool checked: false
    property int size: 34
    property int iconSize: size >= 40 ? 20 : 16
    property real corner: -1        // explicit corner radius (e.g. Material's rounded-square FAB)
    // Override for the icon tint (e.g. white on the lyrics screen); undefined = automatic.
    property var iconColor: undefined
    readonly property bool hovered: ma.containsMouse
    // Tooltip for icon-only buttons (GNOME shows one on every icon button).
    // Defaults from the icon name; set tip: "" to hide or a text to override.
    readonly property var defaultTips: ({
        back: "Voltar", menu: "Menu principal", sidebar: "Barra lateral", shuffle: "Aleatório",
        prev: "Anterior", next: "Próxima", repeat: "Repetir", repeat1: "Repetir esta música",
        lyrics: "Letra", more: "Mais opções", refresh: "Buscar a letra de novo", edit: "Editar",
        close: "Fechar", star: "Tirar dos favoritos", unstar: "Favoritar", playlist: "Adicionar a uma playlist",
        queue: "Fila", add: "Adicionar", trash: "Remover", remove: "Remover", "pan-down": "Fechar a letra",
        download: "Baixar", sort: "Ordenar", search: "Buscar", settings: "Preferências", undo: "Desfazer"
    })
    property string tip: text === "" ? (defaultTips[icon] || "") : ""
    signal clicked()

    implicitWidth: text !== "" ? label.implicitWidth + 24 : size
    implicitHeight: size
    radius: corner >= 0 ? corner : circular || (Theme.pillButtons && text === "") ? height / 2 : Math.min(Theme.radius, height / 2)
    readonly property color fill: destructive ? Theme.destructive : Theme.accent
    color: (suggested || destructive) ? (ma.pressed ? Qt.darker(fill, 1.15) : ma.containsMouse ? Qt.lighter(fill, 1.08) : fill)
         : checked ? Theme.selected
         : ma.pressed ? Theme.pressed : ma.containsMouse ? Theme.hover : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }

    Icon {
        anchors.centerIn: parent
        visible: root.text === "" && root.icon !== ""
        name: root.icon
        size: root.iconSize
        color: root.iconColor !== undefined ? root.iconColor : root.suggested ? Theme.accentInk : root.destructive ? "white" : (root.checked ? Theme.accentFg : Theme.fg)
    }
    Text {
        id: label
        anchors.centerIn: parent
        visible: root.text !== ""
        text: root.text
        color: root.suggested ? Theme.accentInk : root.destructive ? "white" : Theme.fg
        font.family: Theme.font
        font.pointSize: root.text !== "" ? Theme.fontSize : Math.round(root.size * 0.36)
        font.weight: root.text !== "" ? Font.DemiBold : Font.Normal
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // After a click the tooltip stays away until the pointer leaves, so it
        // never covers the menu or popup the button just opened.
        property bool tipBlocked: false
        onPressed: tipBlocked = true
        onExited: tipBlocked = false
        onClicked: root.clicked()
    }
    C.ToolTip {
        id: tt
        visible: root.tip !== "" && ma.containsMouse && !ma.tipBlocked
        delay: 600
        text: root.tip
        contentItem: Text { text: tt.text; color: Theme.toastFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
        background: Rectangle { color: Theme.toastBg; radius: Theme.material ? 4 : 6; opacity: 0.95 }
    }
}
