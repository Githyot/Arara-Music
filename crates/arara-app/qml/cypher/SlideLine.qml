import QtQuick

// Linha diagonal do slide (8/10 sobe, 10\8 desce), da nota de antes até a
// nota do slide, em coordenadas do item pai.
Rectangle {
    id: line
    property real fromX: 0
    property real toX: 0
    property real midY: 0
    property bool up: true
    property real rise: 8
    readonly property real dx: Math.max(4, toX - fromX)
    x: fromX
    y: midY + (up ? rise / 2 : -rise / 2) - height / 2
    width: Math.sqrt(dx * dx + rise * rise)
    height: 2
    radius: 1
    antialiasing: true
    transformOrigin: Item.Left
    rotation: Math.atan2(up ? -rise : rise, dx) * 180 / Math.PI
}
