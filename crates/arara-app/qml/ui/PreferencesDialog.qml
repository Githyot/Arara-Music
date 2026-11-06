import QtQuick
import QtQuick.Controls.Basic
import AraraStyle

// Preferences (AdwPreferencesDialog / macOS Settings / Android settings /
// Windows Settings, depending on the look). Reads `prefs` and writes through
// `set(key, value)`; Main applies every change live.
Item {
    id: dlg
    property var prefs: ({})
    property var setFn: null
    property string page: "look"
    signal chooseFolders()
    signal rescan()
    signal resetAll()
    function set(k, v) { if (setFn) setFn(k, v) }
    function get(k) { return prefs[k] }
    function open() { visible = true; card.forceActiveFocus() }
    function close() { visible = false }

    visible: false
    z: 60

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.5 : 0.3)
        opacity: dlg.visible ? 1 : 0
        MouseArea { anchors.fill: parent; onClicked: dlg.close() }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 32)
        height: Math.min(640, parent.height - 32)
        radius: Theme.dialogRadius
        color: Theme.windowBg
        border.color: Theme.border; border.width: Theme.gnome ? 0 : 1
        clip: true
        focus: true
        Keys.onEscapePressed: dlg.close()
        MouseArea { anchors.fill: parent }   // swallow clicks

        // ---------- navigation ----------
        Rectangle {
            id: nav
            width: dlg.width < 640 ? 64 : 200
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            color: Theme.sidebarBg
            radius: card.radius
            Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: card.radius; color: parent.color }
            Rectangle { visible: Theme.gnome; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.border; opacity: 0.6 }
            Text {
                id: navTitle
                visible: nav.width > 100
                x: Theme.material ? 20 : 16; y: 18
                text: "Preferências"
                color: Theme.fg
                font.family: Theme.displayFont; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 58; margins: 8 }
                spacing: 2
                Repeater {
                    model: [
                        { k: "look", i: "palette", t: "Aparência" },
                        { k: "play", i: "play", t: "Reprodução" },
                        { k: "lyrics", i: "lyrics", t: "Letras" },
                        { k: "library", i: "albums", t: "Biblioteca" },
                        { k: "advanced", i: "settings", t: "Avançado" }
                    ]
                    SidebarRow {
                        required property var modelData
                        width: parent.width
                        icon: modelData.i
                        text: nav.width > 100 ? modelData.t : ""
                        current: dlg.page === modelData.k
                        onClicked: { dlg.page = modelData.k; scroller.contentY = 0 }
                    }
                }
            }
        }

        // ---------- content ----------
        Item {
            anchors { left: nav.right; right: parent.right; top: parent.top; bottom: parent.bottom }
            Text {
                id: pageTitle
                x: 28; y: 18
                text: ({ look: "Aparência", play: "Reprodução", lyrics: "Letras", library: "Biblioteca", advanced: "Avançado" })[dlg.page]
                color: Theme.fg
                font.family: Theme.displayFont; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight
            }
            FlatButton {
                anchors { right: parent.right; top: parent.top; margins: 12 }
                icon: "close"; circular: true; size: 30
                onClicked: dlg.close()
            }
            Flickable {
                id: scroller
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 56 }
                contentHeight: body.height + 32
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: body
                    x: 24; width: scroller.width - 48
                    spacing: 22

                    // ======== Aparência ========
                    Group {
                        visible: dlg.page === "look"
                        title: "Tema"
                        description: "O visual inteiro muda: barra lateral, botões, controles e tipografia."
                        flat: true
                        Flow {
                            width: parent.width
                            spacing: 12
                            Repeater {
                                model: [
                                    { k: "gnome", t: "GNOME" },
                                    { k: "apple", t: "Apple" },
                                    { k: "material", t: "Android" },
                                    { k: "fluent", t: "Windows" }
                                ]
                                ThemeCard {
                                    required property var modelData
                                    look: modelData.k; label: modelData.t
                                    width: Math.max(120, Math.floor((body.width - 36) / 4))
                                    selected: dlg.get("theme") === modelData.k
                                    onClicked: dlg.set("theme", modelData.k)
                                }
                            }
                        }
                    }
                    Group {
                        visible: dlg.page === "look"
                        title: "Cores"
                        ChoiceRow {
                            title: "Estilo"
                            options: [{ v: "system", t: "Sistema" }, { v: "light", t: "Claro" }, { v: "dark", t: "Escuro" }]
                            value: dlg.get("scheme")
                            onPicked: (v) => dlg.set("scheme", v)
                        }
                        RowBase {
                            title: "Cor de destaque"
                            subtitle: dlg.get("accent") === "cover" ? "Muda com a capa da música tocando"
                                    : dlg.get("accent") === "system" ? "A mesma do sistema"
                                    : dlg.get("accent") === "theme" ? "A cor própria de cada tema" : "Cor escolhida"
                            tall: true
                            Column {
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Segmented {
                                    anchors.right: parent.right
                                    options: [{ v: "theme", t: "Do tema" }, { v: "system", t: "Sistema" }, { v: "cover", t: "Capa" }]
                                    value: dlg.get("accent")
                                    onPicked: (v) => dlg.set("accent", v)
                                }
                                Row {
                                    anchors.right: parent.right
                                    spacing: 6
                                    Repeater {
                                        model: ["#3584e4", "#2190a4", "#3a944a", "#c88800", "#ed5b00", "#e62d42", "#d56199", "#9141ac", "#6f8396"]
                                        Rectangle {
                                            required property string modelData
                                            width: 22; height: 22; radius: 11
                                            color: modelData
                                            border.width: dlg.get("accent") === modelData ? 2 : 0
                                            border.color: Theme.fg
                                            Icon { anchors.centerIn: parent; visible: dlg.get("accent") === modelData; name: "check"; size: 12; color: "white" }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dlg.set("accent", parent.modelData) }
                                        }
                                    }
                                }
                            }
                        }
                        SwitchRow {
                            title: "Fundo do player com as cores da capa"
                            subtitle: "Desligado, o painel usa um fundo neutro escuro"
                            checked: dlg.get("panelcolors")
                            onToggled: dlg.set("panelcolors", !checked)
                        }
                    }
                    Group {
                        visible: dlg.page === "look"
                        title: "Layout"
                        ChoiceRow {
                            title: "Tamanho das capas"
                            options: [{ v: "small", t: "Pequeno" }, { v: "medium", t: "Médio" }, { v: "large", t: "Grande" }]
                            value: dlg.get("tilesize")
                            onPicked: (v) => dlg.set("tilesize", v)
                        }
                        SliderRow {
                            title: "Tamanho do texto"
                            from: 0.85; to: 1.3; step: 0.05
                            value: dlg.get("fontscale")
                            label: Math.round(value * 100) + "%"
                            onMoved: (v) => dlg.set("fontscale", v)
                        }
                        SwitchRow {
                            title: "Modo compacto"
                            subtitle: "Linhas mais baixas na barra lateral e nas listas"
                            checked: dlg.get("compact")
                            onToggled: dlg.set("compact", !checked)
                        }
                        SwitchRow {
                            title: "Reduzir animações"
                            subtitle: "Sem zoom da capa, deslizes e transições de página"
                            checked: dlg.get("reducemotion")
                            onToggled: dlg.set("reducemotion", !checked)
                        }
                    }

                    // ======== Reprodução ========
                    Group {
                        visible: dlg.page === "play"
                        title: "Volume"
                        SwitchRow {
                            title: "Normalizar volume (ReplayGain)"
                            subtitle: "Usa as tags de ganho para que as músicas toquem no mesmo volume"
                            checked: dlg.get("replaygain")
                            onToggled: dlg.set("replaygain", !checked)
                        }
                        ChoiceRow {
                            enabled: dlg.get("replaygain")
                            title: "Modo"
                            subtitle: "Álbum mantém as diferenças entre faixas de um mesmo disco"
                            options: [{ v: "track", t: "Faixa" }, { v: "album", t: "Álbum" }]
                            value: dlg.get("rgmode")
                            onPicked: (v) => dlg.set("rgmode", v)
                        }
                        SliderRow {
                            enabled: dlg.get("replaygain")
                            title: "Pré-amplificação"
                            subtitle: "Ajuste aplicado junto com o ReplayGain"
                            from: -12; to: 0; step: 0.5
                            value: dlg.get("preamp")
                            label: (value > 0 ? "+" : "") + value.toFixed(1).replace(".", ",") + " dB"
                            onMoved: (v) => dlg.set("preamp", v)
                        }
                    }
                    Group {
                        visible: dlg.page === "play"
                        title: "Fila"
                        SwitchRow {
                            title: "Reprodução automática"
                            subtitle: "Quando a fila acabar, continua com músicas parecidas"
                            checked: dlg.get("autoplay")
                            onToggled: dlg.set("autoplay", !checked)
                        }
                        SwitchRow {
                            title: "Retomar de onde parou"
                            subtitle: "Ao abrir o app, volta a fila e a posição da última música"
                            checked: dlg.get("restore")
                            onToggled: dlg.set("restore", !checked)
                        }
                        ChoiceRow {
                            title: "Tempo à direita da barra"
                            options: [{ v: "remaining", t: "Restante" }, { v: "total", t: "Duração" }]
                            value: dlg.get("remaining") ? "remaining" : "total"
                            onPicked: (v) => dlg.set("remaining", v === "remaining")
                        }
                    }

                    // ======== Letras ========
                    Group {
                        visible: dlg.page === "lyrics"
                        title: "Busca"
                        SwitchRow {
                            title: "Baixar letras automaticamente"
                            subtitle: "Procura no LRCLIB as letras que não estão ao lado dos arquivos"
                            checked: dlg.get("autolyrics")
                            onToggled: dlg.set("autolyrics", !checked)
                        }
                    }
                    Group {
                        visible: dlg.page === "lyrics"
                        title: "Exibição"
                        SwitchRow {
                            title: "Letra no painel do player"
                            subtitle: "Mostra a letra embaixo dos controles; clique para ampliar"
                            checked: dlg.get("lyricspanel")
                            onToggled: dlg.set("lyricspanel", !checked)
                        }
                        SwitchRow {
                            title: "Separar duetos"
                            subtitle: "Segunda voz do lado direito, como no Apple Music"
                            checked: dlg.get("duets")
                            onToggled: dlg.set("duets", !checked)
                        }
                        ChoiceRow {
                            title: "Tamanho da letra"
                            options: [{ v: 0.85, t: "Pequeno" }, { v: 1, t: "Médio" }, { v: 1.2, t: "Grande" }]
                            value: dlg.get("lyricsscale")
                            onPicked: (v) => dlg.set("lyricsscale", v)
                        }
                        SliderRow {
                            title: "Ajuste de sincronia"
                            subtitle: "Adianta ou atrasa todas as letras sincronizadas"
                            from: -2000; to: 2000; step: 100
                            value: dlg.get("lyricsoffset")
                            label: (value > 0 ? "+" : "") + (value / 1000).toFixed(1).replace(".", ",") + " s"
                            onMoved: (v) => dlg.set("lyricsoffset", v)
                        }
                    }

                    // ======== Biblioteca ========
                    Group {
                        visible: dlg.page === "library"
                        title: "Arquivos"
                        ButtonRow {
                            title: "Pastas de música"
                            subtitle: "Escolha quais pastas fazem parte da biblioteca"
                            button: "Gerenciar…"
                            onClicked: { dlg.close(); dlg.chooseFolders() }
                        }
                        ButtonRow {
                            title: "Reindexar"
                            subtitle: "Lê de novo as tags e capas de todas as pastas"
                            button: "Reindexar agora"
                            onClicked: dlg.rescan()
                        }
                    }
                    Group {
                        visible: dlg.page === "library"
                        title: "Barra lateral"
                        description: "Esconda o que você não usa. As seções podem ser recolhidas clicando no título."
                        Repeater {
                            model: [
                                { k: "genre", t: "Gêneros" }, { k: "year", t: "Anos" }, { k: "composer", t: "Compositores" },
                                { k: "folder", t: "Pastas" }, { k: "added", t: "Adicionadas recentemente" }, { k: "recent", t: "Tocadas recentemente" },
                                { k: "mostplayed", t: "Mais tocadas" }, { k: "free", t: "Música livre" }, { k: "servers", t: "Servidores" }
                            ]
                            SwitchRow {
                                required property var modelData
                                title: modelData.t
                                checked: (dlg.get("hidden") || []).indexOf(modelData.k) < 0
                                onToggled: {
                                    var h = (dlg.get("hidden") || []).slice()
                                    var i = h.indexOf(modelData.k)
                                    if (i >= 0) h.splice(i, 1); else h.push(modelData.k)
                                    dlg.set("hidden", h)
                                }
                            }
                        }
                    }
                    Group {
                        visible: dlg.page === "library"
                        title: "Música livre"
                        SliderRow {
                            title: "Downloads ao mesmo tempo"
                            subtitle: "Vale a partir da próxima vez que o app abrir"
                            from: 1; to: 4; step: 1
                            value: dlg.get("dlworkers")
                            label: String(value)
                            onMoved: (v) => dlg.set("dlworkers", v)
                        }
                        FieldRow {
                            title: "Chave do Jamendo"
                            subtitle: "Grátis em devportal.jamendo.com"
                            text: dlg.get("jamendo") || ""
                            onCommitted: (t) => dlg.set("jamendo", t)
                        }
                    }

                    // ======== Avançado ========
                    Group {
                        visible: dlg.page === "advanced"
                        title: "Janela"
                        ChoiceRow {
                            title: "Botões da janela"
                            subtitle: Theme.apple ? "O tema Apple sempre mostra os três" : "O GNOME mostra só o fechar por padrão"
                            enabled: !Theme.apple
                            options: [{ v: "close", t: "Só fechar" }, { v: "all", t: "Minimizar, maximizar e fechar" }]
                            value: dlg.get("winbuttons")
                            onPicked: (v) => dlg.set("winbuttons", v)
                        }
                    }
                    Group {
                        visible: dlg.page === "advanced"
                        title: "Restaurar"
                        ButtonRow {
                            title: "Voltar às configurações padrão"
                            subtitle: "Tema, cores, reprodução e letras. Biblioteca e playlists não mudam."
                            button: "Restaurar"
                            destructive: true
                            onClicked: dlg.resetAll()
                        }
                    }
                }
            }
        }
    }

    // ---------- building blocks ----------
    // A titled group of rows. GNOME/macOS: one boxed card. Material: tonal card.
    // Fluent: each row is its own card (Windows Settings).
    component Group: Column {
        id: g
        property string title: ""
        property string description: ""
        property bool flat: false
        default property alias rows: inner.data
        width: body.width
        spacing: 8
        Text {
            visible: g.title !== ""
            text: g.title
            color: Theme.fg
            font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.Bold
        }
        Text {
            visible: g.description !== ""
            width: parent.width; wrapMode: Text.Wrap
            text: g.description
            color: Theme.dimFg
            font.family: Theme.font; font.pointSize: Theme.fontSize - 1
        }
        Rectangle {
            width: parent.width
            height: inner.height
            radius: Theme.cardRadius
            color: g.flat || Theme.fluent ? "transparent" : Theme.cardBg
            border.width: g.flat || Theme.fluent || Theme.material ? 0 : 1
            border.color: Theme.border
            clip: !g.flat
            Column {
                id: inner
                width: parent.width
                spacing: Theme.fluent && !g.flat ? 3 : 0
            }
        }
    }

    component RowBase: Rectangle {
        id: rb
        property string title: ""
        property string subtitle: ""
        property bool tall: false
        width: body.width
        height: Math.max(tall ? 84 : (subtitle ? 64 : 52), texts.implicitHeight + 20)
        radius: Theme.fluent ? 4 : 0
        color: Theme.fluent ? Theme.cardBg : "transparent"
        border.width: Theme.fluent ? 1 : 0
        border.color: Theme.border
        opacity: enabled ? 1 : 0.5
        // separator between rows of a boxed list
        Rectangle {
            visible: !Theme.fluent && rb.y > 0
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: Theme.apple ? 14 : 0 }
            height: 1; color: Theme.border; opacity: Theme.material ? 0 : 0.7
        }
        Column {
            id: texts
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 14 + rb.trailingWidth }
            spacing: 2
            Text { width: parent.width; text: rb.title; color: Theme.fg; elide: Text.ElideRight; font.family: Theme.font; font.pointSize: Theme.fontSize }
            Text { visible: rb.subtitle !== ""; width: parent.width; text: rb.subtitle; color: Theme.dimFg; wrapMode: Text.Wrap; font.family: Theme.font; font.pointSize: Theme.fontSize - 1.5 }
        }
        property real trailingWidth: 200
    }

    component SwitchRow: RowBase {
        id: sr
        property bool checked: false
        signal toggled()
        trailingWidth: tg.width + 12
        Toggle { id: tg; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } checked: sr.checked; onToggled: sr.toggled() }
        MouseArea { anchors { fill: parent; rightMargin: tg.width + 20 } cursorShape: Qt.PointingHandCursor; onClicked: sr.toggled() }
    }

    component ChoiceRow: RowBase {
        id: cr
        property var options: []
        property var value
        signal picked(var v)
        trailingWidth: seg.width + 12
        Segmented { id: seg; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } options: cr.options; value: cr.value; onPicked: (v) => cr.picked(v) }
    }

    component SliderRow: RowBase {
        id: slr
        property real from: 0
        property real to: 1
        property real step: 0.1
        property real value: 0
        property string label: ""
        signal moved(real v)
        trailingWidth: 250
        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10
            ThemedSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: 170
                from: slr.from; to: slr.to; stepSize: slr.step; snapMode: Slider.SnapAlways
                value: slr.value
                onMoved: slr.moved(value)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 64; horizontalAlignment: Text.AlignRight
                text: slr.label; color: Theme.dimFg
                font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
        }
    }

    component ButtonRow: RowBase {
        id: br
        property string button: ""
        property bool destructive: false
        signal clicked()
        trailingWidth: bt.width + 12
        FlatButton {
            id: bt
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: br.button
            color: br.destructive ? (hovered ? Qt.rgba(1, 0, 0, 0.12) : Theme.hover) : (hovered ? Theme.pressed : Theme.hover)
            onClicked: br.clicked()
        }
    }

    component FieldRow: RowBase {
        id: fr
        property string text: ""
        signal committed(string t)
        trailingWidth: 232
        Rectangle {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 220; height: 34; radius: Math.min(Theme.radius, 8)
            color: Theme.fieldBg
            border.color: fi.activeFocus ? Theme.accent : Theme.fluent ? Theme.border : "transparent"; border.width: fi.activeFocus ? 2 : 1
            TextInput {
                id: fi
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter
                text: fr.text; clip: true
                color: Theme.fg; selectionColor: Theme.accent; selectedTextColor: Theme.accentInk
                font.family: Theme.font; font.pointSize: Theme.fontSize
                onEditingFinished: if (text !== fr.text) fr.committed(text.trim())
            }
        }
    }

    // Segmented buttons in the current look (GNOME linked buttons, macOS
    // segmented control, Material segmented button, Fluent selector bar).
    component Segmented: Rectangle {
        id: sg
        property var options: []
        property var value
        signal picked(var v)
        width: segRow.width + (Theme.material ? 0 : 4); height: Theme.material ? 36 : 30
        radius: Theme.material ? height / 2 : Math.min(Theme.radius + 1, 8)
        color: Theme.material ? "transparent" : Theme.fieldBg
        border.width: Theme.material || Theme.fluent ? 1 : 0
        border.color: Theme.material ? (Theme.dark ? "#938f99" : "#79747e") : Theme.border
        clip: true
        Row {
            id: segRow
            x: Theme.material ? 0 : 2; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: sg.options
                Rectangle {
                    id: seg
                    required property var modelData
                    required property int index
                    readonly property bool on: sg.value === modelData.v
                    width: segText.implicitWidth + (Theme.material && on ? 44 : 26); height: sg.height - (Theme.material ? 0 : 4)
                    radius: Theme.material ? 0 : sg.radius - 2
                    readonly property color fillColor: on ? (Theme.material ? Theme.selected : Theme.apple || Theme.fluent ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : "white") : Theme.selected)
                         : sm.containsMouse ? Theme.hover : "transparent"
                    color: Theme.material ? "transparent" : fillColor
                    // Material: the end segments follow the pill's round ends.
                    Item {
                        visible: Theme.material
                        anchors.fill: parent
                        readonly property bool first: seg.index === 0
                        readonly property bool last: seg.index === sg.options.length - 1
                        Rectangle { anchors.fill: parent; radius: parent.first || parent.last ? height / 2 : 0; color: seg.fillColor }
                        Rectangle { visible: parent.first && !parent.last; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: parent.width / 2; color: seg.fillColor }
                        Rectangle { visible: parent.last && !parent.first; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: parent.width / 2; color: seg.fillColor }
                    }
                    border.width: on && (Theme.apple || Theme.fluent) && !Theme.dark ? 0.5 : 0
                    border.color: Qt.rgba(0, 0, 0, 0.12)
                    Rectangle { visible: Theme.material && seg.index > 0; width: 1; height: parent.height + 4; y: -2; color: sg.border.color }
                    Rectangle {
                        visible: Theme.fluent && seg.on
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 2 }
                        width: 14; height: 3; radius: 1.5; color: Theme.accent
                    }
                    Row {
                        anchors.centerIn: parent; spacing: 6
                        Icon { visible: Theme.material && seg.on; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 14 }
                        Text {
                            id: segText
                            anchors.verticalCenter: parent.verticalCenter
                            text: seg.modelData.t
                            color: Theme.fg
                            font.family: Theme.font; font.pointSize: Theme.fontSize - 1
                            font.weight: seg.on ? Font.DemiBold : Font.Normal
                        }
                    }
                    MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sg.picked(seg.modelData.v) }
                }
            }
        }
    }

    // Miniature of each look, drawn with its own palette and shapes.
    component ThemeCard: Column {
        id: tc
        property string look: "gnome"
        property string label: ""
        property bool selected: false
        signal clicked()
        spacing: 8
        readonly property bool dk: Theme.dark
        readonly property var pal: ({
            gnome:    { win: dk ? "#222226" : "#fafafb", side: dk ? "#2e2e32" : "#ebebed", acc: "#3584e4", r: 6,  tile: 4, sel: dk ? "#3a3a3e" : "#dcdcdf" },
            apple:    { win: dk ? "#1e1e1e" : "#ffffff", side: dk ? "#2c2c2e" : "#f0f0f2", acc: "#fa2d48", r: 8,  tile: 3, sel: dk ? "#3a3a3c" : "#e2e2e6" },
            material: { win: dk ? "#1d1a22" : "#fdf7fd", side: dk ? "#26222d" : "#f1ebf6", acc: dk ? "#d0bcff" : "#6750a4", r: 12, tile: 6, sel: dk ? "#4a4458" : "#e8def8" },
            fluent:   { win: dk ? "#202020" : "#f3f3f3", side: dk ? "#202020" : "#f3f3f3", acc: dk ? "#60cdff" : "#005fb8", r: 4,  tile: 3, sel: dk ? "#2d2d2d" : "#e9e9e9" }
        })[look]
        Rectangle {
            width: tc.width; height: Math.round(tc.width * 0.66)
            radius: 10
            color: tc.pal.win
            clip: true
            // border drawn on top, so the miniature never covers it
            Rectangle {
                z: 2; anchors.fill: parent; radius: parent.radius; color: "transparent"
                border.width: tc.selected ? 3 : 1
                border.color: tc.selected ? Theme.accent : Theme.border
            }
            // sidebar
            Rectangle {
                x: tc.look === "apple" ? 5 : 0; y: tc.look === "apple" ? 5 : 0
                width: parent.width * 0.3; height: parent.height - (tc.look === "apple" ? 10 : 0)
                radius: tc.look === "apple" ? 5 : 0
                color: tc.pal.side
                Row {
                    visible: tc.look === "apple"
                    x: 5; y: 5; spacing: 3
                    Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; Rectangle { required property string modelData; width: 5; height: 5; radius: 2.5; color: modelData } }
                }
                Column {
                    x: 4; y: 16; width: parent.width - 8; spacing: 3
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            width: parent.width; height: 8; radius: tc.look === "material" ? 4 : 2
                            color: index === 0 ? tc.pal.sel : "transparent"
                            Rectangle { visible: tc.look === "fluent" && index === 0; width: 2; height: 4; y: 2; radius: 1; color: tc.pal.acc }
                            Rectangle { x: 5; y: 3; width: parent.width * 0.55; height: 2; radius: 1; color: tc.look === "apple" && index === 0 ? tc.pal.acc : Qt.rgba(0.5, 0.5, 0.5, 0.6) }
                        }
                    }
                }
            }
            // content: Fluent puts it on a layer with a rounded corner
            Rectangle {
                x: parent.width * 0.3 + (tc.look === "apple" ? 5 : 0); y: tc.look === "fluent" ? 8 : 0
                width: parent.width - x; height: parent.height - y
                radius: tc.look === "fluent" ? 4 : 0
                color: tc.look === "fluent" ? (tc.dk ? "#272727" : "#f9f9f9") : "transparent"
                Grid {
                    x: 8; y: 10; columns: 3; spacing: 5
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            width: (tc.width * 0.7 - 30) / 3; height: width; radius: tc.pal.tile
                            color: Qt.hsla((index * 0.13 + 0.55) % 1, 0.45, tc.dk ? 0.42 : 0.7, 1)
                        }
                    }
                }
                // play button in the look's shape
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 7 }
                    width: 16; height: 16
                    radius: tc.look === "material" ? 5 : 8
                    color: tc.look === "apple" ? "transparent" : tc.pal.acc
                    Icon { anchors.centerIn: parent; name: "play"; size: tc.look === "apple" ? 12 : 9; color: tc.look === "apple" ? tc.pal.acc : (tc.look === "material" && tc.dk) || (tc.look === "fluent" && tc.dk) ? "#1c1b1f" : "white" }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tc.clicked() }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tc.label
            color: tc.selected ? Theme.accentFg : Theme.fg
            font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: tc.selected ? Font.DemiBold : Font.Normal
        }
    }
}
