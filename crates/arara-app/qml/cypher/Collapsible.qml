import QtQuick
import QtQuick.Layouts
import AraraCypher

// Grupo que abre e fecha: um cabeçalho clicável (seta, título, selo opcional)
// e o conteúdo. Fechado, mostra um resumo de uma linha no cabeçalho.
Column {
    id: root
    property string title
    property string summary         // aparece só quando está fechado
    property string badge           // ex.: "2×"
    property string hint            // texto pequeno à direita, sempre visível
    property bool expanded: true
    // Parte que está tocando agora (modo Estudar do Arara Music).
    property bool active: false
    onActiveChanged: if (active) expanded = true
    // Treino de ouvido: a parte da vez fica coberta até a pessoa conferir.
    property bool concealed: false
    default property alias body: inner.data
    spacing: 6

    Rectangle {
        id: header
        width: root.width
        height: Math.max(32, headerRow.implicitHeight + 10)
        radius: Theme.radiusSmall
        color: root.active ? Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, Theme.dark ? 0.22 : 0.13)
             : mouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: 200 } }

        RowLayout {
            id: headerRow
            x: 4
            width: parent.width - 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                text: "›"
                rotation: root.expanded ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 120 } }
                Layout.preferredWidth: 14
                horizontalAlignment: Text.AlignHCenter
                color: Theme.textDim
                font.pixelSize: Theme.fontSize + 6
                font.weight: Font.Bold
            }
            Text {
                text: root.title
                color: root.active ? Theme.chord : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.weight: Font.Bold
            }
            Rectangle {
                visible: root.badge.length > 0
                Layout.preferredWidth: badgeText.implicitWidth + 12
                Layout.preferredHeight: badgeText.implicitHeight + 4
                radius: height / 2
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.badge
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    font.weight: Font.Bold
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.concealed ? "acordes escondidos: tire de ouvido" : root.expanded ? "" : root.summary
                elide: Text.ElideRight
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                visible: root.hint.length > 0
                text: root.hint
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    Column {
        id: inner
        visible: root.expanded && !root.concealed
        width: root.width
        spacing: 10
    }
}
