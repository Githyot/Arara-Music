import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import AraraStyle

// Import playlists and likes from Apple Music / YouTube Music exports.
// Step 1 explains how to export; step 2 shows what matched and what's missing.
Popup {
    id: dlg
    property bool busy: false
    property var report: null
    signal importPath(string path)
    signal pickRequested(bool directory)

    function start() { busy = false; report = null; open() }
    function finished(json) { busy = false; report = JSON.parse(json) }
    function pick(url) { pickedPath(decodeURIComponent(url.toString().replace(/^file:\/\//, ""))) }
    function pickedPath(path) { if (!visible) open(); report = null; busy = true; importPath(path) }
    function fallback(directory) { if (directory) folderDialog.open(); else fileDialog.open() }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, parent.width - 24)
    height: Math.min(implicitHeight, parent.height - 24)
    modal: true
    focus: true
    padding: 24
    closePolicy: busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    Overlay.modal: Rectangle { color: "#4d000000" }
    background: Rectangle { radius: Theme.dialogRadius; color: Theme.popupBg; border.color: Theme.border; border.width: Theme.fluent || Theme.apple ? 1 : 0 }

    FileDialog {
        id: fileDialog
        title: "Escolha o arquivo exportado"
        nameFilters: ["Exportações (*.xml *.csv *.json *.m3u *.m3u8 *.xspf)", "Todos os arquivos (*)"]
        onAccepted: dlg.pick(selectedFile)
    }
    FolderDialog {
        id: folderDialog
        title: "Escolha a pasta exportada (ex.: Takeout descompactado)"
        onAccepted: dlg.pick(selectedFolder)
    }

    component Step: Row {
        property string n: ""
        property string text: ""
        width: parent.width; spacing: 10
        Rectangle {
            width: 22; height: 22; radius: 11; color: Theme.hover
            Text { anchors.centerIn: parent; text: parent.parent.n; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2; font.weight: Font.Bold }
        }
        Text { width: parent.width - 32; wrapMode: Text.Wrap; text: parent.text; textFormat: Text.StyledText; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
    }

    contentItem: Column {
        spacing: 12
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "import"; size: 44; color: Theme.dimFg }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: dlg.report && dlg.report.ok ? "Importação concluída" : "Importar playlists e curtidas"; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.headingSize; font.weight: Theme.headingWeight }

        // ---- instructions ----
        Column {
            visible: !dlg.report || !dlg.report.ok
            width: parent.width; spacing: 10
            Text {
                width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                text: "As playlists viram playlists do Arara com as músicas que você já tem (locais ou no seu servidor) e as curtidas viram favoritas. O áudio continua só no serviço."
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1
            }
            Step { n: "1"; text: "<b>Apple Music:</b> no app Música (Mac) ou iTunes (Windows), <i>Arquivo › Biblioteca › Exportar Biblioteca…</i> e escolha o <i>Library.xml</i>." }
            Step { n: "2"; text: "<b>YouTube Music:</b> em takeout.google.com, exporte só <i>YouTube e YouTube Music</i>, descompacte e escolha a pasta." }
            Step { n: "3"; text: "<b>Outros:</b> CSV do Exportify, TuneMyMusic ou Soundiiz, e playlists M3U/XSPF." }
            Row {
                visible: !!(dlg.report && !dlg.report.ok)
                width: parent.width; spacing: 8
                Icon { id: w; name: "warning"; size: 16; color: Theme.destructive }
                Text { width: parent.width - w.width - 8; wrapMode: Text.Wrap; text: dlg.report && dlg.report.error ? "Não deu certo: " + dlg.report.error : ""; color: Theme.destructive; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
            }
        }

        // ---- report ----
        Column {
            visible: !!(dlg.report && dlg.report.ok)
            width: parent.width; spacing: 8
            Rectangle {
                width: parent.width; height: stats.height + 24; radius: Theme.cardRadius; color: Theme.hover
                Column {
                    id: stats
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                    spacing: 4
                    Text { text: dlg.report ? dlg.report.matched + " de " + dlg.report.total + " músicas encontradas na sua biblioteca" : ""; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize; font.weight: Font.DemiBold }
                    Text { text: dlg.report ? dlg.report.playlists + (dlg.report.playlists === 1 ? " playlist criada" : " playlists criadas") + " · " + dlg.report.starred + " curtidas viraram favoritas" : ""; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                    Text { visible: !!(dlg.report && dlg.report.unreadable > 0); text: !dlg.report ? "" : dlg.report.unreadable === 1 ? "1 item veio só com o ID do vídeo, sem nome, e não dá para procurar" : dlg.report.unreadable + " itens vieram só com o ID do vídeo, sem nome, e não dá para procurar"; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                }
            }
            Text {
                visible: !!(dlg.report && dlg.report.missing && dlg.report.missing.length > 0)
                text: "Faltando na sua biblioteca (" + (dlg.report && dlg.report.missing ? dlg.report.missing.length : 0) + ")"
                color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1; font.weight: Font.Bold
            }
            ListView {
                id: missingList
                visible: count > 0
                width: parent.width; height: Math.min(contentHeight, 210)
                clip: true
                model: dlg.report && dlg.report.missing ? dlg.report.missing : []
                delegate: Item {
                    required property var modelData
                    width: missingList.width; height: 40
                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        Text { width: parent.width; elide: Text.ElideRight; text: modelData.title; color: Theme.fg; font.family: Theme.font; font.pointSize: Theme.fontSize - 1 }
                        Text { width: parent.width; elide: Text.ElideRight; text: (modelData.artist || "?") + " · " + modelData.playlist; color: Theme.dimFg; font.family: Theme.font; font.pointSize: Theme.fontSize - 2 }
                    }
                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border; opacity: 0.5 }
                }
            }
        }

        Item { width: 1; height: 2 }
        Row {
            spacing: 10
            anchors.horizontalCenter: parent.horizontalCenter
            FlatButton {
                visible: !dlg.report || !dlg.report.ok
                text: "Cancelar"; color: Theme.hover; width: 140; opacity: dlg.busy ? 0.5 : 1
                onClicked: if (!dlg.busy) dlg.close()
            }
            FlatButton {
                visible: !dlg.report || !dlg.report.ok
                text: dlg.busy ? "Importando…" : "Escolher arquivo…"; suggested: true; width: 160
                onClicked: if (!dlg.busy) dlg.pickRequested(false)
            }
            FlatButton {
                visible: !dlg.report || !dlg.report.ok
                text: "Escolher pasta…"; color: Theme.hover; width: 140
                onClicked: if (!dlg.busy) dlg.pickRequested(true)
            }
            FlatButton {
                visible: !!(dlg.report && dlg.report.ok)
                text: "Concluir"; suggested: true; width: 160
                onClicked: dlg.close()
            }
        }
    }
}
