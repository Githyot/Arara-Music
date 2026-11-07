use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    // style.qrc files are not tracked by cxx-qt-build; rebuild when they change.
    println!("cargo:rerun-if-changed=qml/style");
    println!("cargo:rerun-if-changed=style.qrc");
    CxxQtBuilder::new_qml_module(QmlModule::new("io.github.arara")
        .qml_files([
        "qml/ui/Main.qml",
        "qml/ui/HeaderBar.qml",
        "qml/ui/FlatButton.qml",
        "qml/ui/SidebarRow.qml",
        "qml/ui/AlbumGrid.qml",
        "qml/ui/AlbumPage.qml",
        "qml/ui/TrackRow.qml",
        "qml/ui/ExplicitBadge.qml",
        "qml/ui/SongsPage.qml",
        "qml/ui/PlayerBar.qml",
        "qml/ui/CoverArt.qml",
        "qml/ui/FastScroll.qml",
        "qml/ui/GroupsPage.qml",
        "qml/ui/PlayerControls.qml",
        "qml/ui/SpeedPopup.qml",
        "qml/ui/PlayerPanel.qml",
        "qml/ui/LyricsScreen.qml",
        "qml/ui/VolumeSlider.qml",
        "qml/ui/FreePage.qml",
        "qml/ui/SortMenu.qml",
        "qml/ui/FoldersDialog.qml",
        "qml/ui/LyricsView.qml",
        "qml/ui/Sidebar.qml",
        "qml/ui/ArtistGrid.qml",
        "qml/ui/TrackListPage.qml",
        "qml/ui/TrackMenu.qml",
        "qml/ui/TextPrompt.qml",
        "qml/ui/QueueView.qml",
        "qml/ui/DragReorder.qml",
        "qml/ui/LyricsEditor.qml",
        "qml/ui/InfoSection.qml",
        "qml/ui/InfoPage.qml",
        "qml/ui/InfoBar.qml",
            "qml/ui/AddServerDialog.qml",
            "qml/ui/ServerPage.qml",
            "qml/ui/AppMenu.qml",
            "qml/ui/ImportDialog.qml",
            "qml/ui/PreferencesDialog.qml",
            "qml/ui/SectionHeader.qml",
    ]))
    // Theme singleton lives in its own tiny module so every file can `import AraraStyle`.
    .qrc("style.qrc")
    .qt_module("Quick")
    .qt_module("Multimedia")
    .files(["src/bridge.rs", "src/models.rs"])
    .build();
}
