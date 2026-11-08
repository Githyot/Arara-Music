import QtQuick
import AraraCypher

// Caixa agrupada: "boxed list" no GNOME, "inset grouped" na Apple.
Rectangle {
    id: card
    default property alias content: inner.data
    property int padding: 14

    radius: Theme.radius
    color: Theme.card
    border.width: Theme.apple ? 0 : 1
    border.color: Theme.dark ? "transparent" : Qt.rgba(0, 0, 0, 0.07)
    implicitHeight: inner.implicitHeight + padding * 2
    implicitWidth: inner.implicitWidth + padding * 2

    Column {
        id: inner
        x: card.padding
        y: card.padding
        width: card.width - card.padding * 2
        spacing: 10
    }
}
