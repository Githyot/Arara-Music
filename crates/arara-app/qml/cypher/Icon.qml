import QtQuick
import QtQuick.Shapes
import AraraCypher

// Ícone simbólico do tema, pintado com qualquer cor.
Item {
    id: root
    property string name
    property color color: Theme.text
    property real size: 16

    implicitWidth: size
    implicitHeight: size
    // A camada fica no tamanho final, para o ícone escalado não ficar borrado.
    layer.enabled: true
    layer.samples: 4
    layer.smooth: true

    Shape {
        width: 16
        height: 16
        scale: root.size / 16
        transformOrigin: Item.TopLeft

        ShapePath {
            strokeWidth: -1
            fillColor: root.color
            fillRule: ShapePath.OddEvenFill
            PathSvg { path: Theme.icons[root.name] || "" }
        }
    }
}
