import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import AraraCypher
import io.github.arara as Arara

// Editor de cifra: dados da música, batidas, partes (acordes, tablatura,
// repetições) e as formas dos acordes. Também lê uma cifra colada.
// A música fica num objeto JS (`draft`); os campos de texto escrevem direto
// nele, e mudanças de estrutura (somar/tirar partes, batidas) aumentam `rev`
// para as listas se redesenharem.
Rectangle {
    id: page
    color: Theme.window

    property var draft: null
    property int rev: 0
    property string editingChord: ""     // acorde com a forma aberta para editar
    property string message: ""

    signal saved(var song)
    signal closed()

    readonly property var codes: ["", "B", "D", "d", "U", "X", "XU"]
    readonly property var codeLabel: ({ "": "·", "B": "baixo", "D": "tudo", "d": "acorde", "U": "agudas", "X": "abafa ↓", "XU": "abafa ↑" })

    function defaultStrum() {
        return { name: "Batida", pattern: ["B", "", "d", "U", "", "U", "d", "U"],
                 counts: ["1", "e", "2", "e", "3", "e", "4", "e"] }
    }

    function blank() {
        return { title: "", artist: "", key: "C", capo: 0, video: "", fretsReal: true,
                 strums: [defaultStrum()], voicings: {},
                 sections: [{ name: "Intro", repeat: 1, chords: [] }] }
    }

    // Abre uma música para editar (null = nova). Exemplos viram uma cópia.
    function load(song) {
        var d = song ? JSON.parse(JSON.stringify(song)) : blank()
        if (!d.strums) d.strums = d.strum ? [d.strum] : [defaultStrum()]
        if (!d.voicings) d.voicings = {}
        if (!d.sections) d.sections = []
        if (d.capo === undefined) d.capo = 0
        if (d.video === undefined) d.video = ""
        // Partes abertas só quando são poucas; com muitas, abre uma por vez.
        for (var i = 0; i < d.sections.length; ++i) {
            d.sections[i]._open = d.sections.length <= 2
            // Setas da tab embaixo do toque certo (1ª seta = 1º toque).
            if (d.sections[i].tab) d.sections[i].tab = Arara.CypherMusic.alignArrows(d.sections[i].tab)
        }
        draft = d
        pasteFold.expanded = !song
        editingChord = ""
        message = ""
        pasteArea.text = ""
        rev++
        flick.contentY = 0
    }

    function bump() { rev++ }

    function chordsOf(text) {
        return text.split(/\s+/).filter(function (t) { return t.length > 0 })
    }

    // Acordes diferentes da música, na ordem em que aparecem.
    readonly property var distinctChords: {
        rev
        var out = []
        if (!draft) return out
        var add = function (c) { if (c && out.indexOf(c) < 0 && Arara.CypherMusic.isChord(Examples.chordName(c))) out.push(c) }
        for (var i = 0; i < draft.sections.length; ++i) {
            var sec = draft.sections[i]
            for (var j = 0; j < sec.chords.length; ++j) add(sec.chords[j])
            // Também os acordes marcados na tab (Acorde neste toque).
            if (sec.tab) JSON.parse(Arara.CypherMusic.tabModel(sec.tab)).forEach(function (sys) {
                (sys.chords || []).forEach(function (m) { add(m.name) })
            })
        }
        return out
    }

    function readPaste(replace) {
        var link = pasteArea.text.trim()
        if (/^https?:\/\/\S+$/i.test(link)) { readLink(link, replace); return }
        if (applySong(JSON.parse(Arara.CypherLibrary.parseSong(pasteArea.text)), replace, ""))
            pasteArea.text = ""
    }

    // Põe na música o que foi lido (texto, arquivo ou link). Com "substituir",
    // troca partes, batidas e dados; senão, acrescenta as partes no fim.
    function applySong(song, replace, label) {
        if (!song.sections || song.sections.length === 0) {
            message = "Não achei acordes nem tablatura" + (label ? " em " + label : " nesse texto") + "."
            return false
        }
        var take = function (k) { return song[k] && (replace || !draft[k]) }
        if (take("title")) draft.title = song.title
        if (take("artist")) draft.artist = song.artist
        if (song.key && replace) draft.key = song.key
        if (song.capo && replace) draft.capo = song.capo
        // O importador já põe as formas na casa de verdade (contando o capo).
        if (replace || !draft.voicings || Object.keys(draft.voicings).length === 0) draft.fretsReal = true
        if (song.bpm && (replace || !draft.bpm)) draft.bpm = song.bpm
        var parts = song.sections
        if (song.strums && song.strums.length > 0) {
            var offset = replace ? 0 : draft.strums.length
            draft.strums = replace ? song.strums : draft.strums.concat(song.strums)
            for (var i = 0; i < parts.length; ++i)
                if (parts[i].strum !== undefined) parts[i].strum += offset
        }
        for (var k in song.voicings) if (replace || !draft.voicings[k]) draft.voicings[k] = song.voicings[k]
        for (var j = 0; j < parts.length; ++j) parts[j]._open = parts.length <= 2
        draft.sections = replace ? parts : draft.sections.concat(parts)
        var extras = []
        if (song.strums && song.strums.length) extras.push(song.strums.length === 1 ? "1 batida" : song.strums.length + " batidas")
        if (song.bpm) extras.push(song.bpm + " BPM")
        var nv = Object.keys(song.voicings || {}).length
        if (nv) extras.push(nv === 1 ? "1 forma de acorde" : nv + " formas de acorde")
        message = "Li " + (parts.length === 1 ? "1 parte" : parts.length + " partes")
                + (extras.length ? ", " + extras.join(", ") : "")
                + (song.title ? " de " + song.title : "") + ". Confira e toque em Salvar."
        pasteFold.expanded = false
        bump()
        return true
    }

    // Link colado: baixa a página (como o navegador faria), tira a cifra e
    // preenche a música. A letra fica de fora; nada sai do computador.
    function readLink(url, replace) {
        message = "Abrindo o link..."
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status < 200 || xhr.status >= 300 || !xhr.responseText) {
                page.message = "Não consegui abrir o link" + (xhr.status ? " (erro " + xhr.status + ")" : "")
                        + ". Veja se o endereço está certo e se há internet. Se o site não deixar, copie o texto da cifra e cole aqui."
                return
            }
            var p = JSON.parse(Arara.CypherLibrary.readPage(xhr.responseText))
            var song = JSON.parse(Arara.CypherLibrary.parseSong(p.text || ""))
            // O que a página diz fora da cifra vale mais que o palpite do texto.
            if (p.title) song.title = p.title
            if (p.artist) song.artist = p.artist
            if (p.key) song.key = p.key
            if (p.capo) song.capo = p.capo
            if (p.bpm && !song.bpm) song.bpm = p.bpm
            if (page.applySong(song, replace, "nessa página")) {
                if (!page.draft.source) page.draft.source = url
                pasteArea.text = ""
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    // Lê o texto de um print (OCR no próprio computador) e põe no campo de
    // colar, para conferir antes de ler as partes.
    property string pendingImage: ""
    function readImage(url) {
        var path = decodeURIComponent(String(url).replace(/^file:\/\//, ""))
        if (/\.(txt|text|cho|crd|pro|chopro)$/i.test(path)) { readTextFile(path); return }
        pendingImage = path
        message = "Lendo o print..."
        ocrTimer.start()
    }
    // Arquivo .txt de cifra: lê direto (numa música nova, já preenche tudo).
    function readTextFile(path) {
        var text = Arara.CypherLibrary.readTextFile(path)
        if (!text) { message = "Não consegui abrir o arquivo."; return }
        var empty = draft.sections.every(function (s) { return s.chords.length === 0 && !s.tab })
        if (empty) {
            applySong(JSON.parse(Arara.CypherLibrary.parseSong(text)), true, "nesse arquivo")
        } else {
            pasteArea.text = text
            message = "Abri o arquivo. Confira o texto e toque em Ler e substituir ou Ler e acrescentar."
        }
    }
    Timer {
        id: ocrTimer
        interval: 60
        onTriggered: {
            var r = JSON.parse(Arara.CypherLibrary.readImage(page.pendingImage))
            if (r.ok && r.text.trim().length > 0) {
                pasteArea.text = r.text
                page.message = "Li o print. Confira o texto abaixo (o leitor pode errar uma letra ou outra) e toque em Ler."
            } else {
                page.message = r.ok ? "Não achei texto nessa imagem." : r.text
            }
        }
    }
    FileDialog {
        id: imageDialog
        title: "Escolha o print ou o arquivo da cifra"
        nameFilters: ["Prints e arquivos de cifra (*.png *.jpg *.jpeg *.webp *.bmp *.txt *.cho *.pro)",
                      "Imagens (*.png *.jpg *.jpeg *.webp *.bmp)", "Texto (*.txt *.cho *.pro)"]
        onAccepted: page.readImage(selectedFile)
    }

    // Arrastar partes pela alça: onde a parte arrastada vai entrar
    // (índice da parte que fica logo depois dela, ou o total para o fim).
    property int dropBefore: -1
    function dropSlot(from, centerY) {
        var n = draft.sections.length
        for (var j = 0; j < n; ++j) {
            if (j === from) continue
            var it = partsRepeater.itemAt(j)
            if (it && centerY < it.y + it.height / 2) return (j === from + 1) ? -1 : j
        }
        return from === n - 1 ? -1 : n
    }
    function finishDrag(row) {
        var from = row.index
        var to = dropBefore
        row.dragging = false
        row.dragDy = 0
        dropBefore = -1
        if (to < 0 || to === from || to === from + 1) return
        var s = draft.sections.splice(from, 1)[0]
        draft.sections.splice(to > from ? to - 1 : to, 0, s)
        bump()
    }

    function startVoicing(chord) {
        if (!draft.voicings[chord]) {
            var s = Examples.shape(chord, 0, null)
            draft.voicings[chord] = s ? { frets: s.frets.slice(), fingers: s.fingers.slice() }
                                      : { frets: [-1, -1, -1, -1, -1, -1], fingers: [0, 0, 0, 0, 0, 0] }
        }
        editingChord = chord
        bump()
    }

    // Campos que começam com "_" (ex.: _open) são só da tela e não vão para o arquivo.
    function noPrivate(k, v) { return k.charAt(0) === "_" ? undefined : v }

    function save() {
        if (!draft.title || draft.title.trim().length === 0) draft.title = "Sem título"
        // Partes vazias (sem acordes, sem tab e sem nota) não vão para o arquivo.
        draft.sections = draft.sections.filter(function (s) {
            return s.chords.length > 0 || (s.tab && s.tab.length > 0) || (s.note && s.note.length > 0)
        })
        // Formas de acordes que saíram da música também.
        var keep = {}
        for (var k in draft.voicings)
            if (distinctChords.indexOf(k) >= 0) keep[k] = draft.voicings[k]
        draft.voicings = keep
        var id = Arara.CypherLibrary.save(JSON.stringify(draft, page.noPrivate))
        if (id.length === 0) {
            message = "Não consegui salvar. Veja se a pasta " + Arara.CypherLibrary.folder + " pode ser gravada."
            return
        }
        draft.id = id
        saved(JSON.parse(JSON.stringify(draft, page.noPrivate)))
    }

    Component.onCompleted: if (!draft) load(null)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        HeaderBar {
            Layout.fillWidth: true
            title: page.draft && page.draft.id ? "Editar cifra" : "Nova cifra"
            AppButton { text: "Cancelar"; flat: true; onClicked: page.closed() }
            AppButton { text: "Salvar"; suggested: true; onClicked: page.save() }
        }

        Flickable {
            id: flick
            ScrollBar.vertical: AppScrollBar {}
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: body.implicitHeight + 2 * Theme.pagePadding
            clip: true

            Column {
                id: body
                y: Theme.pagePadding
                width: Math.min(parent.width - 2 * Theme.pagePadding, 1400)
                x: (parent.width - width) / 2
                spacing: 10

                Text {
                    visible: page.message.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: page.message
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                // ---- Dados ----
                Collapsible {
                    width: parent.width
                    title: "Música"
                    id: infoFold
                    summary: page.rev, page.draft ? [page.draft.title || "Sem título", page.draft.artist, "Tom " + page.draft.key].filter(function (s) { return !!s }).join(" · ") : ""
                    Card {
                        width: parent.width
                        GridLayout {
                            width: parent.width
                            columns: width > 520 ? 2 : 1
                            columnSpacing: 10
                            rowSpacing: 8
                            AppTextField {
                                Layout.fillWidth: true
                                placeholderText: "Título"
                                text: page.rev, page.draft ? page.draft.title : ""
                                onTextEdited: page.draft.title = text
                            }
                            AppTextField {
                                Layout.fillWidth: true
                                placeholderText: "Artista"
                                text: page.rev, page.draft ? (page.draft.artist || "") : ""
                                onTextEdited: page.draft.artist = text
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: "Tom"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                AppTextField {
                                    Layout.preferredWidth: 90
                                    mono: true
                                    placeholderText: "C"
                                    text: page.rev, page.draft ? (page.draft.key || "") : ""
                                    onTextEdited: page.draft.key = text
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Capo"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                AppButton {
                                    iconName: "remove"
                                    onClicked: { page.draft.capo = Math.max(0, (page.draft.capo || 0) - 1); page.bump() }
                                }
                                Text {
                                    Layout.preferredWidth: 28
                                    horizontalAlignment: Text.AlignHCenter
                                    text: page.rev, page.draft && page.draft.capo ? page.draft.capo : "—"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                AppButton {
                                    iconName: "add"
                                    onClicked: { page.draft.capo = Math.min(12, (page.draft.capo || 0) + 1); page.bump() }
                                }
                                Text {
                                    text: "BPM"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                AppTextField {
                                    Layout.preferredWidth: 64
                                    mono: true
                                    placeholderText: "—"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    text: page.rev, page.draft && page.draft.bpm ? String(page.draft.bpm) : ""
                                    onTextEdited: { var n = parseInt(text); if (n > 0) page.draft.bpm = n; else delete page.draft.bpm }
                                }
                            }
                            AppTextField {
                                Layout.fillWidth: true
                                placeholderText: "Link do vídeo (YouTube)"
                                text: page.rev, page.draft ? (page.draft.video || "") : ""
                                onTextEdited: page.draft.video = text
                            }
                        }
                    }
                }

                // Cifras importadas antes da correção do capotraste guardaram as
                // formas contando a partir do capo; um toque soma o capo nelas.
                Card {
                    visible: page.rev, !!page.draft && (page.draft.capo || 0) > 0 && !page.draft.fretsReal
                             && Object.keys(page.draft.voicings || {}).length > 0
                    width: parent.width
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: page.rev, page.draft ? "As formas desta cifra podem estar contando a partir do capotraste (ex.: 10 em vez de " + (10 + (page.draft.capo || 0)) + "). Isso acontecia nas cifras importadas antes desta versão." : ""
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Row {
                        spacing: 8
                        AppButton {
                            suggested: true
                            text: page.rev, page.draft ? "Corrigir as casas (+" + (page.draft.capo || 0) + ")" : ""
                            onClicked: {
                                for (var k in page.draft.voicings) {
                                    var v = page.draft.voicings[k]
                                    for (var i = 0; i < 6; ++i) if (v.frets[i] > 0) v.frets[i] += page.draft.capo
                                }
                                page.draft.fretsReal = true
                                page.message = "Casas corrigidas. Toque em Salvar."
                                page.bump()
                            }
                        }
                        AppButton {
                            flat: true
                            text: "Estão certas"
                            onClicked: { page.draft.fretsReal = true; page.bump() }
                        }
                    }
                }

                // ---- Colar cifra ----
                Collapsible {
                    width: parent.width
                    title: "Colar cifra ou print"
                    id: pasteFold
                    summary: "texto de site, tab ou imagem"
                    Card {
                        width: parent.width
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Cole o link de uma cifra, o texto copiado de um site ou uma tablatura, ou abra um print (também dá para arrastar a imagem para cá). O app pega as partes ([Intro], [Refrão]...), os acordes, as repetições (2x) e as linhas de tab. A letra fica de fora."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        AppTextArea {
                            DropArea {
                                anchors.fill: parent
                                keys: ["text/uri-list"]
                                onDropped: (drop) => { if (drop.hasUrls) page.readImage(drop.urls[0]) }
                            }
                            id: pasteArea
                            width: parent.width
                            height: 140
                            placeholderText: "https://... (link da cifra)\n\nou o texto:\n[Intro] Am  F  C  G\n\n[Refrão]\nC        G\n..."
                        }
                        Flow {
                            width: parent.width
                            spacing: 8
                            AppButton {
                                text: "Abrir print ou arquivo..."
                                onClicked: imageDialog.open()
                            }
                            AppButton {
                                text: "Ler e substituir as partes"
                                enabled: pasteArea.text.length > 0
                                onClicked: page.readPaste(true)
                            }
                            AppButton {
                                text: "Ler e acrescentar"
                                enabled: pasteArea.text.length > 0
                                onClicked: page.readPaste(false)
                            }
                        }
                    }
                }

                // ---- Batidas ----
                Collapsible {
                    width: parent.width
                    title: "Batidas"
                    id: strumFold
                    expanded: false
                    summary: page.rev, page.draft ? page.draft.strums.map(function (s) { return s.pattern.map(function (p) { return Examples.strokeArrow(p) }).join(" ") }).join("   |   ") : ""
                    Repeater {
                        model: page.rev, page.draft ? page.draft.strums : []
                        Card {
                            id: strumCard
                            required property var modelData
                            required property int index
                            // A batida de verdade no rascunho (modelData é uma cópia).
                            readonly property var st: page.rev, page.draft.strums[index] || modelData
                            width: body.width
                            RowLayout {
                                width: parent.width
                                Text {
                                    text: (strumCard.index + 1) + "."
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                AppTextField {
                                    Layout.fillWidth: true
                                    text: strumCard.st.name
                                    placeholderText: "Nome da batida"
                                    onTextEdited: strumCard.st.name = text
                                }
                                AppButton {
                                    text: "Apagar batida"
                                    flat: true
                                    onClicked: {
                                        page.draft.strums.splice(strumCard.index, 1)
                                        for (var i = 0; i < page.draft.sections.length; ++i) {
                                            var s = page.draft.sections[i].strum || 0
                                            if (s === strumCard.index) delete page.draft.sections[i].strum
                                            else if (s > strumCard.index) page.draft.sections[i].strum = s - 1
                                        }
                                        page.bump()
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                text: "Toque em cada tempo para trocar: · pausa, baixo, tudo, acorde (sem o baixo), agudas (para cima), abafado para baixo (↓×) e para cima (↑×). O “>” no canto (ou clique direito) marca a palhetada forte (⬇ ⬆)."
                                wrapMode: Text.WordWrap
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                            StrumSlots {
                                width: parent.width
                                strum: strumCard.st
                                rev: page.rev
                                onChanged: page.bump()
                            }
                        }
                    }
                        AppButton {
                            text: "Nova batida"
                            iconName: "add"
                            flat: true
                            onClicked: { var s = page.defaultStrum(); s.name = "Batida " + (page.draft.strums.length + 1); page.draft.strums.push(s); page.bump() }
                        }
                }

                // ---- Partes ----
                Collapsible {
                    width: parent.width
                    title: "Partes"
                    id: partsFold
                    summary: page.rev, page.draft ? page.draft.sections.map(function (s) { return s.name }).join(" · ") : ""
                    RowLayout {
                        width: parent.width
                        AppButton { text: "Abrir todas"; flat: true; onClicked: { page.draft.sections.forEach(function (s) { s._open = true }); page.bump() } }
                        AppButton { text: "Fechar todas"; flat: true; onClicked: { page.draft.sections.forEach(function (s) { s._open = false }); page.bump() } }
                        Item { Layout.fillWidth: true }
                        AppButton {
                            text: "Nova parte"
                            iconName: "add"
                            flat: true
                            onClicked: { page.draft.sections.push({ name: "Parte " + (page.draft.sections.length + 1), repeat: 1, chords: [], _open: true }); page.bump() }
                        }
                    }
                    Repeater {
                        id: partsRepeater
                        model: page.rev, page.draft ? page.draft.sections : []
                        Item {
                            id: partRow
                            required property var modelData
                            required property int index
                            property real dragDy: 0
                            property bool dragging: false
                            width: body.width
                            height: secCard.height
                            z: dragging ? 10 : 0
                            opacity: dragging ? 0.85 : 1
                            transform: Translate { y: partRow.dragDy }

                            // Linha que mostra onde a parte vai entrar.
                            Rectangle {
                                visible: page.dropBefore === partRow.index || (page.dropBefore === page.draft.sections.length && partRow.index === page.draft.sections.length - 1)
                                x: handle.width + 6
                                width: parent.width - x
                                height: 3
                                radius: 1.5
                                y: page.dropBefore === partRow.index ? -6 : parent.height + 3
                                color: Theme.accent
                            }

                            // Alça de arrastar, do lado de fora do cartão.
                            Rectangle {
                                id: handle
                                width: 26
                                height: Math.min(secCard.height, 40)
                                radius: Theme.radiusSmall
                                color: handleMouse.containsMouse || partRow.dragging
                                       ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08) : "transparent"
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Repeater {
                                        model: 3
                                        Rectangle { width: 14; height: 2; radius: 1; color: Theme.textDim }
                                    }
                                }
                                MouseArea {
                                    id: handleMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: partRow.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    property real startY: 0
                                    onPressed: (m) => {
                                        startY = mapToItem(null, m.x, m.y).y
                                        partRow.dragging = true
                                    }
                                    onPositionChanged: (m) => {
                                        if (!partRow.dragging) return
                                        partRow.dragDy = mapToItem(null, m.x, m.y).y - startY
                                        page.dropBefore = page.dropSlot(partRow.index, partRow.y + partRow.dragDy + partRow.height / 2)
                                    }
                                    onReleased: page.finishDrag(partRow)
                                    onCanceled: page.finishDrag(partRow)
                                }
                            }
                            Card {
                                id: secCard
                                // A parte de verdade no rascunho (o modelData da Repeater é uma cópia:
                                // mudar nela não chega no arquivo salvo).
                                readonly property var modelData: page.rev, page.draft.sections[partRow.index] || partRow.modelData
                                readonly property int index: partRow.index
                                property bool showTab: !!modelData.tab
                                x: handle.width + 6
                            width: parent.width - x
                                padding: partFold.expanded ? 14 : 4
                                Collapsible {
                                    id: partFold
                                    width: parent.width
                                    title: secCard.modelData.name || "Parte sem nome"
                                    badge: page.rev, (secCard.modelData.repeat || 1) > 1 ? secCard.modelData.repeat + "×" : ""
                                    summary: page.rev, secCard.modelData.chords.join("  ")
                                             + (page.draft.strums.length > 1 && secCard.modelData.chords.length && page.draft.strums[Math.min(secCard.modelData.strum || 0, page.draft.strums.length - 1)]
                                                ? "  · " + (page.draft.strums[Math.min(secCard.modelData.strum || 0, page.draft.strums.length - 1)].name || "batida") : "")
                                             + (secCard.modelData.tab ? (secCard.modelData.chords.length ? "  · " : "") + "tab" : "")
                                    expanded: !!secCard.modelData._open
                                    onExpandedChanged: secCard.modelData._open = expanded
    
                                    RowLayout {
                                        width: parent.width
                                        spacing: 6
                                        AppTextField {
                                            Layout.fillWidth: true
                                            text: secCard.modelData.name
                                            placeholderText: "Nome da parte (Intro, Refrão...)"
                                            onTextEdited: secCard.modelData.name = text
                                        }
                                        AppButton {
                                            iconName: "remove"
                                            onClicked: { secCard.modelData.repeat = Math.max(1, (secCard.modelData.repeat || 1) - 1); page.bump() }
                                        }
                                        Text {
                                            text: page.rev, (secCard.modelData.repeat || 1) + "×"
                                            color: Theme.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.weight: Font.Bold
                                        }
                                        AppButton {
                                            iconName: "add"
                                            onClicked: { secCard.modelData.repeat = (secCard.modelData.repeat || 1) + 1; page.bump() }
                                        }
                                    }
    
                                    AppTextField {
                                        id: chordField
                                        width: parent.width
                                        mono: true
                                        placeholderText: "Acordes separados por espaço: Am F C G"
                                        text: secCard.modelData.chords.join("  ")
                                        onTextEdited: secCard.modelData.chords = page.chordsOf(text)
                                        onEditingFinished: page.bump()
                                        readonly property var bad: page.chordsOf(text).filter(function (c) {
                                            return !Arara.CypherMusic.isChord(Examples.chordName(c))
                                        })
                                    }
                                    Text {
                                        visible: chordField.bad.length > 0
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: "Não reconheci: " + chordField.bad.join(", ")
                                        color: Theme.destructive
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                    }
    
                                    // Batida desta parte: escolher uma das batidas, criar uma só
                                    // para ela, e mexer nos tempos aqui mesmo.
                                    Column {
                                        visible: secCard.modelData.chords.length > 0
                                        width: parent.width
                                        spacing: 6
                                        readonly property int si: page.rev, Math.min(secCard.modelData.strum || 0, page.draft.strums.length - 1)
                                        readonly property var strum: page.rev, page.draft.strums[si]
                                        readonly property int users: page.rev, page.draft.sections.filter(function (x) {
                                            return x.chords.length > 0 && Math.min(x.strum || 0, page.draft.strums.length - 1) === si }).length
                                        id: partStrum
                                        Text {
                                            text: "Batida desta parte"
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.weight: Font.DemiBold
                                        }
                                        Flow {
                                            width: parent.width
                                            spacing: 6
                                            Repeater {
                                                model: page.rev, page.draft.strums.slice()
                                                AppButton {
                                                    required property var modelData
                                                    required property int index
                                                    text: modelData.name || ("Batida " + (index + 1))
                                                    suggested: index === partStrum.si
                                                    onClicked: { secCard.modelData.strum = index; page.bump() }
                                                }
                                            }
                                            AppButton {
                                                text: "Batida só desta parte"
                                                iconName: "add"
                                                flat: true
                                                onClicked: {
                                                    var c = JSON.parse(JSON.stringify(partStrum.strum || page.defaultStrum()))
                                                    c.name = secCard.modelData.name || ("Batida " + (page.draft.strums.length + 1))
                                                    page.draft.strums.push(c)
                                                    secCard.modelData.strum = page.draft.strums.length - 1
                                                    page.bump()
                                                }
                                            }
                                        }
                                        Text {
                                            visible: !partStrum.strum
                                            text: "Sem batida: cada acorde aparece com um toque só. Escolha ou crie uma batida acima."
                                            color: Theme.textDim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 1
                                        }
                                        StrumSlots {
                                            visible: !!partStrum.strum
                                            width: parent.width
                                            slotW: 44
                                            strum: partStrum.strum
                                            rev: page.rev
                                            onChanged: page.bump()
                                        }
                                        Text {
                                            visible: partStrum.users > 1
                                            width: parent.width
                                            wrapMode: Text.WordWrap
                                            text: "Essa batida vale para " + partStrum.users + " partes. Para mudar só esta, toque em \"Batida só desta parte\"."
                                            color: Theme.textDim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                    }


                                    AppTextArea {
                                        visible: secCard.showTab
                                        width: parent.width
                                        height: Math.max(120, contentHeight + 24)
                                        placeholderText: "e|-----------------|\nB|-----------------|\nG|-----5-----------|\nD|---7-------------|\nA|-----------------|\nE|-----------------|"
                                        text: secCard.modelData.tab || ""
                                        onTextChanged: secCard.modelData.tab = text
                                        id: tabArea
                                    }
    
                                    // Setas x toques: a 1ª seta é do 1º toque, e assim por diante.
                                    Text {
                                        readonly property var bad: {
                                            if (!secCard.showTab || !tabArea.text) return []
                                            var out = [], sys = JSON.parse(Arara.CypherMusic.lessonTab(tabArea.text))
                                            for (var i = 0; i < sys.length; ++i)
                                                if (sys[i].arrows > 0 && sys[i].arrows !== sys[i].events.length)
                                                    out.push("bloco " + (i + 1) + ": " + sys[i].events.length + " toques e " + sys[i].arrows + " setas")
                                            return out
                                        }
                                        visible: bad.length > 0
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: "As setas não batem com os toques (" + bad.join("; ") + "). Cada toque precisa de uma seta; o app liga as que dá pela posição."
                                        color: Theme.destructive
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 1
                                    }
                                    TabEditor {
                                        visible: secCard.showTab
                                        width: parent.width
                                        text: visible ? tabArea.text : ""
                                        onEdited: (t) => { tabArea.text = t }
                                    }
    
                                    AppTextField {
                                        width: parent.width
                                        placeholderText: "Observação (opcional)"
                                        text: secCard.modelData.note || ""
                                        onTextEdited: secCard.modelData.note = text
                                    }
    
                                    Row {
                                        spacing: 6
                                        AppButton {
                                            text: secCard.showTab ? "Sem tab" : "Tab (riff, solo)"
                                            onClicked: {
                                                if (secCard.showTab) delete secCard.modelData.tab
                                                else secCard.modelData.tab = ""
                                                secCard.showTab = !secCard.showTab
                                            }
                                        }
                                        AppButton {
                                            text: "Apagar"
                                            onClicked: { page.draft.sections.splice(secCard.index, 1); page.bump() }
                                        }
                                }
                                }
                            }
                        }
                    }
                }

                // ---- Formas ----
                Collapsible {
                    width: parent.width
                    title: "Formas dos acordes"
                    id: shapesFold
                    expanded: false
                    summary: page.distinctChords.join("  ")
                    Card {
                        width: parent.width
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: page.distinctChords.length === 0
                                  ? "Os acordes das partes aparecem aqui."
                                  : "Toque num acorde para abrir o editor de braço e mudar a forma (casas, dedos, O e X). Para o mesmo acorde com duas formas, escreva com apelido: Gm7@2."
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Flow {
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: page.distinctChords
                                Rectangle {
                                    id: vbox
                                    required property string modelData
                                    readonly property bool custom: page.rev, !!page.draft.voicings[modelData]
                                    width: 104
                                    height: vname.implicitHeight + vdiag.implicitHeight + 28
                                    radius: Theme.radiusSmall
                                    color: page.editingChord === modelData
                                           ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                           : Qt.rgba(Theme.chord.r, Theme.chord.g, Theme.chord.b, Theme.dark ? 0.16 : 0.09)
                                    Text {
                                        id: vname
                                        y: 6
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: vbox.modelData + (vbox.custom ? " ✎" : "")
                                        color: Theme.chord
                                        font.family: Theme.monoFamily
                                        font.pixelSize: Theme.fontSize + 2
                                        font.weight: Font.Bold
                                    }
                                    ChordDiagram {
                                        id: vdiag
                                        anchors.top: vname.bottom
                                        anchors.topMargin: 6
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        chord: Examples.chordName(vbox.modelData)
                                        voicing: page.rev, page.draft.voicings[vbox.modelData] || null
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.editingChord === vbox.modelData ? page.editingChord = ""
                                                                                        : page.startVoicing(vbox.modelData)
                                    }
                                }
                            }
                        }
                    }
                    // Editor da forma escolhida.
                    Card {
                        id: voicingCard
                        visible: page.editingChord.length > 0 && !!page.draft.voicings[page.editingChord]
                        width: parent.width
                        readonly property var v: page.rev, page.draft && page.editingChord ? page.draft.voicings[page.editingChord] : null

                        RowLayout {
                            width: parent.width
                            Text {
                                Layout.fillWidth: true
                                text: "Forma de " + page.editingChord
                                color: Theme.chord
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 2
                                font.weight: Font.Bold
                            }
                            AppButton {
                                text: "Usar a do app"
                                onClicked: { delete page.draft.voicings[page.editingChord]; page.editingChord = ""; page.bump() }
                            }
                            AppButton {
                                // A tab manda: reescreve os toques desse acorde com a forma nova.
                                text: "Aplicar na tab"
                                onClicked: {
                                    var n = 0
                                    page.draft.sections.forEach(function (sec) {
                                        if (!sec.tab) return
                                        var r = Examples.applyShapeToTab(sec.tab, page.editingChord, voicingCard.v.frets)
                                        sec.tab = r.tab; n += r.changed
                                    })
                                    page.message = n ? n + " toques de " + page.editingChord + " mudaram na tab." : "Nenhum toque marcado com " + page.editingChord + " precisou mudar."
                                    page.bump()
                                }
                            }
                            AppButton { text: "Pronto"; suggested: true; onClicked: page.editingChord = "" }
                        }

                        Text {
                            visible: page.message !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: page.message
                            color: Theme.success
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }
                        // Editor de braço: clicar na casa põe o dedo, em cima troca O/X.
                        ChordEditor {
                            width: parent.width
                            voicing: voicingCard.v
                            chord: page.editingChord
                            capo: page.draft && page.draft.fretsReal ? (page.draft.capo || 0) : 0
                            rev: page.rev
                            onChanged: page.bump()
                        }
                    }
                }


                // ---- Fim ----
                Row {
                    spacing: 8
                    AppButton { text: "Salvar"; suggested: true; onClicked: page.save() }
                    AppButton { text: "Cancelar"; onClicked: page.closed() }
                    AppButton {
                        visible: !!(page.draft && page.draft.id)
                        text: "Apagar cifra"
                        onClicked: deleteConfirm.visible = true
                    }
                }
                Card {
                    id: deleteConfirm
                    visible: false
                    width: parent.width
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Apagar \"" + (page.draft ? page.draft.title : "") + "\" da sua biblioteca? Não dá para desfazer."
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Row {
                        spacing: 8
                        AppButton {
                            text: "Apagar"
                            onClicked: { Arara.CypherLibrary.remove(page.draft.id); deleteConfirm.visible = false; page.draft = null; page.load(null); page.closed() }
                        }
                        AppButton { text: "Não apagar"; onClicked: deleteConfirm.visible = false }
                    }
                }
                Item { width: 1; height: 24 }
            }
        }
    }
}
