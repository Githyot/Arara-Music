pragma Singleton
import QtQuick
import Qt.labs.settings
import AraraStyle as A

// Fica numa subpasta de propósito: se estivesse em qml/ junto com os outros
// arquivos, o import implícito da pasta esconderia o singleton do módulo.
//
// Tema global do app. Dois estilos visuais (GNOME/Adwaita e Apple) e três
// esquemas de cor (sistema, claro, escuro). Tudo na interface lê as cores,
// raios e fontes daqui, então trocar o estilo muda o app inteiro na hora.
QtObject {
    id: theme

    // ---- Dentro do Arara Music ----
    // A aba Estudos segue o visual do Arara: estilo Apple quando o Arara está
    // no Apple, GNOME nos outros (Material e Fluent usam a base GNOME), e o
    // claro/escuro e a cor de destaque escolhidos nas Preferências do Arara.
    readonly property string style: A.Theme.apple ? "apple" : "gnome"
    property real chordZoom: 1          // tamanho dos acordes na tela da música
    // Partitura: batida de acorde (3+ cordas juntas) como barra de ritmo
    // em vez das notas empilhadas. A tab continua com todas as notas.
    property bool slashChords: true

    property Settings _settings: Settings {
        category: "cypher-appearance"
        property alias chordZoom: theme.chordZoom
        property alias slashChords: theme.slashChords
    }

    readonly property bool apple: style === "apple"
    readonly property bool dark: A.Theme.dark

    // ---- Cores ----
    // GNOME: paleta do libadwaita. Apple: cores de sistema do iOS/macOS.
    readonly property color accent: A.Theme.accent
    readonly property color accentBg: A.Theme.accent
    readonly property color accentFg: A.Theme.accentInk

    readonly property color window: A.Theme.windowBg
    readonly property color view: A.Theme.viewBg
    readonly property color sidebar: A.Theme.sidebarBg
    readonly property color headerBar: A.Theme.headerBg
    readonly property color card: A.Theme.cardBg
    readonly property color text: A.Theme.fg
    readonly property color textDim: A.Theme.dimFg
    readonly property color border: apple ? (dark ? "#38383a" : "#d1d1d6")
                                          : (dark ? "#3a3a3e" : "#dedee1")
    readonly property color button: apple ? (dark ? "#2c2c2e" : "#e5e5ea")
                                          : (dark ? "#3a3a3e" : "#e8e8ea")
    readonly property color buttonHover: Qt.darker(button, dark ? 0.85 : 1.06)
    readonly property color selection: apple ? accent
                                             : (dark ? "#3a3a3e" : "#dcdcdf")
    readonly property color selectionFg: apple ? accentFg : text
    readonly property color destructive: apple ? (dark ? "#ff453a" : "#ff3b30")
                                               : (dark ? "#ff7b63" : "#e01b24")
    readonly property color success: apple ? (dark ? "#30d158" : "#34c759")
                                           : (dark ? "#8ff0a4" : "#2ec27e")
    // Acordes destacados na cifra (usado a partir do passo 2).
    // Cor de cada dedo da mão esquerda (1 indicador ... 4 mínimo), usada no
    // contorno dos números da tab e nos diagramas.
    readonly property var fingerColors: ["transparent",
        dark ? "#62a0ea" : "#1c71d8",   // 1 indicador: azul
        dark ? "#57e389" : "#26a269",   // 2 médio: verde
        dark ? "#f8e45c" : "#c88800",   // 3 anelar: amarelo
        dark ? "#dc8add" : "#9141ac",   // 4 mínimo: roxo
        dark ? "#f66151" : "#c01c28"]   // P polegar: vermelho
    // Cor de cada número de casa na tab (o mesmo número tem sempre a mesma
    // cor, para ler rápido). A corda solta (0) não usa número: vira um anel.
    readonly property var fretPalette: dark
        ? ["#99c1f1", "#8ff0a4", "#f9f06b", "#ffbe6f", "#f66151", "#dc8add", "#62a0ea", "#57e389", "#e5a50a", "#ff7800", "#c061cb", "#5bc8af"]
        : ["#1a5fb4", "#26a269", "#9c6f00", "#c64600", "#c01c28", "#813d9c", "#3584e4", "#2ec27e", "#986a44", "#e66100", "#9141ac", "#1d8a74"]
    function fretColor(f) {
        if (f === 255 || f === "x") return textDim
        var n = parseInt(f)
        if (isNaN(n) || n <= 0) return text
        return fretPalette[(n - 1) % 12]
    }
    readonly property color chord: apple ? (dark ? "#ff9f0a" : "#c93400")
                                         : (dark ? "#ffa348" : "#c64600")

    // ---- Forma ----
    readonly property int radiusSmall: apple ? 8 : 6
    readonly property int radius: apple ? 10 : 12
    readonly property int controlHeight: apple ? 34 : 34
    readonly property bool pillButtons: apple
    readonly property int spacing: 12
    readonly property int pagePadding: 18

    // ---- Tipografia ----
    readonly property string fontFamily: A.Theme.font
    readonly property string monoFamily: _firstAvailable(
        apple ? ["SF Mono", "Menlo", "JetBrains Mono", "DejaVu Sans Mono", "monospace"]
              : ["Adwaita Mono", "Source Code Pro", "DejaVu Sans Mono", "monospace"])
    readonly property int fontSize: apple ? 15 : 14
    readonly property int titleSize: apple ? 30 : 15       // título da página
    readonly property int titleWeight: apple ? Font.Bold : Font.Bold
    readonly property int headingSize: apple ? 20 : 18

    function _firstAvailable(names) {
        var available = Qt.fontFamilies()
        for (var i = 0; i < names.length; ++i)
            if (available.indexOf(names[i]) !== -1)
                return names[i]
        return names[names.length - 1]
    }

    // Ícones simbólicos 16x16 desenhados como caminhos SVG, para poderem ser
    // pintados com a cor do tema sem depender de um tema de ícones do sistema
    // (que não existe no Android).
    readonly property var icons: ({
        "library": "M1 2h3v12H1zM5 2h3v12H5zM9.3 2.8l2.9-.8 2.8 11.2-2.9.8z",
        "edit": "M10.5 1.5l4 4-9 9h-4v-4z",
        "tuner": "M1 7h2v2H1zM4 4h2v8H4zM7 1h2v14H7zM10 4h2v8h-2zM13 6h2v4h-2z",
        "study": "M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zM6 4.8l5.2 3.2L6 11.2z",
        "settings": "M1 3h14v2H1zM1 7h14v2H1zM1 11h14v2H1zM3.5 1.5h3v5h-3zM9.5 5.5h3v5h-3zM5.5 9.5h3v5h-3z",
        "add": "M7 2h2v5h5v2H9v5H7V9H2V7h5z",
        "remove": "M2 7h12v2H2z",
        "note": "M6 2.5l8-2v10a2.5 2.5 0 1 1-1.5-2.3V3.9L7.5 5.2v7.3a2.5 2.5 0 1 1-1.5-2.3z",
        // Modo Estudar (Arara Music)
        "play": "M4 2l10 6-10 6z",
        "pause": "M3 2h4v12H3zM9 2h4v12H9z",
        "rewind": "M8 2v12L1 8zM15 2v12L8 8z",
        "loop": "M3 7a4 4 0 0 1 4-4h5V1l3 3-3 3V5H7a2 2 0 0 0-2 2zM13 9a4 4 0 0 1-4 4H4v2l-3-3 3-3v2h5a2 2 0 0 0 2-2z",
        "speaker": "M1 5h3l4-4v14l-4-4H1zM10 4.5a5 5 0 0 1 0 7l-1-1a3.6 3.6 0 0 0 0-5zM12 2.5a8 8 0 0 1 0 11l-1-1a6.6 6.6 0 0 0 0-9z",
        "mute": "M1 5h3l4-4v14l-4-4H1zM10 5.5l1-1 2 2 2-2 1 1-2 2 2 2-1 1-2-2-2 2-1-1 2-2z",
        "eye": "M8 3C4 3 1 8 1 8s3 5 7 5 7-5 7-5-3-5-7-5zm0 2.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5z",
        "flag": "M3 1h2v14H3zM6 2h8l-2 3 2 3H6z",
        "trash": "M5.5 1h5l.5 1.5H14V4H2V2.5h3zM3 5h10l-.8 10H3.8zM6 7v6h1.3V7zm2.7 0v6H10V7z"
    })
}
