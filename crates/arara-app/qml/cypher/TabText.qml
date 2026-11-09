import QtQuick
import QtQuick.Controls.Basic
import AraraCypher
import io.github.arara as Arara

// Tablatura em texto (do jeito que se cola de sites e aulas: "e|--3--"),
// em fonte de largura fixa, com as casas em destaque. Rola de lado quando
// a linha é mais comprida que a tela.
Flickable {
    id: root
    property string tab
    property real zoom: 1

    implicitHeight: label.implicitHeight + (contentWidth > width ? 14 : 0)
    contentWidth: label.implicitWidth
    contentHeight: label.implicitHeight
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    ScrollBar.horizontal: AppScrollBar {}

    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    readonly property string rich: {
        var lines = Arara.CypherMusic.alignArrows(tab).split("\n")
        var out = []
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i]
            var m = line.match(/^(\s*[EADGBe]\s*\|)(.*)$/)
            if (!m) { out.push(esc(line)); continue }
            var body = esc(m[2])
                .replace(/(\d+)/g, "<b><font color=\"" + Theme.accent + "\">$1</font></b>")
                .replace(/(-+)/g, "<font color=\"" + Theme.textDim + "\">$1</font>")
            out.push("<font color=\"" + Theme.chord + "\"><b>" + esc(m[1]) + "</b></font>" + body)
        }
        return "<pre>" + out.join("\n") + "</pre>"
    }

    Text {
        id: label
        text: root.rich
        textFormat: Text.RichText
        color: Theme.text
        font.family: Theme.monoFamily
        font.pixelSize: Math.round(14 * root.zoom)
    }
}
