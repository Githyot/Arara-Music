use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("io.github.arara")
        .qml_files([
        "qml/ui/Main.qml",
        "qml/ui/HeaderBar.qml",
        "qml/ui/FlatButton.qml",
        "qml/ui/SidebarRow.qml",
        "qml/ui/AlbumGrid.qml",
        "qml/ui/AlbumPage.qml",
        "qml/ui/TrackRow.qml",
        "qml/ui/SongsPage.qml",
        "qml/ui/PlayerBar.qml",
        "qml/ui/NowPlaying.qml",
        "qml/ui/LyricsView.qml",
        "qml/ui/Sidebar.qml",
        "qml/ui/ArtistGrid.qml",
        "qml/ui/TrackListPage.qml",
        "qml/ui/TrackMenu.qml",
        "qml/ui/TextPrompt.qml",
        "qml/ui/QueueView.qml",
        "qml/ui/DragReorder.qml",
    ]))
    // Theme singleton lives in its own tiny module so every file can `import AraraStyle`.
    .qrc("style.qrc")
    .qt_module("Quick")
    .qt_module("Multimedia")
    .files(["src/bridge.rs"])
    .build();
}
