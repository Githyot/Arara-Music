//! Rust ⇄ QML bridge. One `Library` object, created from QML.
//!
//! Data crosses into QML as small JSON strings fetched on demand (one album
//! page, one search result, one lyrics set), so QML never holds the whole
//! library. Covers are plain `file://` URLs to the on-disk thumbnail cache;
//! QML's `Image { asynchronous: true; sourceSize }` decodes only what's
//! visible, and GridView recycles delegates.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, scanning)]
        #[qproperty(QString, status)]
        #[qproperty(i32, track_count, cxx_name = "trackCount")]
        #[qproperty(i32, album_count, cxx_name = "albumCount")]
        #[qproperty(QString, library_dir, cxx_name = "libraryDir")]
        #[qproperty(bool, dark)]
        #[qproperty(QString, accent)]
        #[qproperty(bool, syncing)]
        #[qproperty(QString, lyrics_progress, cxx_name = "lyricsProgress")]
        type Library = super::LibraryRust;

        /// Opens the cached index (instant), starts a background rescan,
        /// folder watching, MPRIS and appearance tracking.
        #[qinvokable]
        fn open(self: Pin<&mut Library>);

        #[qinvokable]
        #[cxx_name = "startScan"]
        fn start_scan(self: Pin<&mut Library>, dir: &QString);

        #[qinvokable]
        #[cxx_name = "albumsJson"]
        fn albums_json(self: &Library) -> QString;

        #[qinvokable]
        #[cxx_name = "albumTracksJson"]
        fn album_tracks_json(self: &Library, album_id: i64) -> QString;

        #[qinvokable]
        #[cxx_name = "artistsJson"]
        fn artists_json(self: &Library) -> QString;

        #[qinvokable]
        #[cxx_name = "artistAlbumsJson"]
        fn artist_albums_json(self: &Library, artist_id: i64) -> QString;

        #[qinvokable]
        #[cxx_name = "searchJson"]
        fn search_json(self: &Library, query: &QString) -> QString;

        /// Categories: kind is "genre", "year", "composer" or "folder".
        #[qinvokable]
        #[cxx_name = "groupsJson"]
        fn groups_json(self: &Library, kind: &QString) -> QString;

        /// Tracks to continue after the queue ends (same artist/genre first).
        #[qinvokable]
        #[cxx_name = "autoplayJson"]
        fn autoplay_json(self: &Library, seed: i64, exclude_json: &QString, count: i32) -> QString;

        /// JSON array of colours sampled from a cover thumbnail URL.
        /// file:// URL of a small blurred copy of a cover, for backgrounds ("" if none).
        #[qinvokable]
        #[cxx_name = "coverBlur"]
        fn cover_blur(self: &Library, url: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "coverColors"]
        fn cover_colors(self: &Library, url: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "starredJson"]
        fn starred_json(self: &Library) -> QString;

        #[qinvokable]
        #[cxx_name = "recentJson"]
        fn recent_json(self: &Library) -> QString;

        #[qinvokable]
        #[cxx_name = "mostPlayedJson"]
        fn most_played_json(self: &Library) -> QString;

        /// Returns the new starred state.
        #[qinvokable]
        #[cxx_name = "setStarred"]
        fn set_starred(self: Pin<&mut Library>, track_id: i64, starred: bool) -> bool;

        /// Mark a track explicit by hand: mode 1 yes, 0 no, -1 back to automatic.
        /// Returns the new state (0 none, 1 explicit, 2 only the lyrics look explicit).
        #[qinvokable]
        #[cxx_name = "setExplicit"]
        fn set_explicit(self: Pin<&mut Library>, track_id: i64, mode: i32) -> i32;

        /// Current explicit state of a track (same values as above).
        #[qinvokable]
        #[cxx_name = "explicitOf"]
        fn explicit_of(self: &Library, track_id: i64) -> i32;

        #[qinvokable]
        #[cxx_name = "recordPlay"]
        fn record_play(self: &Library, track_id: i64);

        #[qinvokable]
        #[cxx_name = "playlistsJson"]
        fn playlists_json(self: &Library) -> QString;

        #[qinvokable]
        #[cxx_name = "playlistTracksJson"]
        fn playlist_tracks_json(self: &Library, playlist_id: i64) -> QString;

        #[qinvokable]
        #[cxx_name = "createPlaylist"]
        fn create_playlist(self: Pin<&mut Library>, name: &QString) -> i64;

        /// Create (id < 0) or edit a smart playlist; returns its id.
        #[qinvokable]
        #[cxx_name = "saveSmartPlaylist"]
        fn save_smart_playlist(self: Pin<&mut Library>, id: i64, name: &QString, query: &QString, sort: &QString, limit: i64) -> i64;

        #[qinvokable]
        #[cxx_name = "renamePlaylist"]
        fn rename_playlist(self: Pin<&mut Library>, playlist_id: i64, name: &QString);

        #[qinvokable]
        #[cxx_name = "deletePlaylist"]
        fn delete_playlist(self: Pin<&mut Library>, playlist_id: i64);

        /// `track_ids_json` is a JSON array of ids.
        #[qinvokable]
        #[cxx_name = "addToPlaylist"]
        fn add_to_playlist(self: Pin<&mut Library>, playlist_id: i64, track_ids_json: &QString);

        #[qinvokable]
        #[cxx_name = "moveInPlaylist"]
        fn move_in_playlist(self: Pin<&mut Library>, playlist_id: i64, from: i64, to: i64);

        #[qinvokable]
        #[cxx_name = "removeFromPlaylist"]
        fn remove_from_playlist(self: Pin<&mut Library>, playlist_id: i64, pos: i64);

        /// `{"ids":[..], "index": n, "pos": ms}`
        #[qinvokable]
        #[cxx_name = "saveQueue"]
        fn save_queue(self: &Library, json: &QString);

        /// `{"tracks":[..], "index": n, "pos": ms}`
        #[qinvokable]
        #[cxx_name = "loadQueue"]
        fn load_queue(self: &Library) -> QString;

        /// Resolves lyrics on a worker thread; answers with `lyricsReady`.
        #[qinvokable]
        #[cxx_name = "requestLyrics"]
        fn request_lyrics(self: Pin<&mut Library>, track_id: i64);

        /// Forget the stored lyrics (wrong version, unsynced) and look them up again.
        #[qinvokable]
        #[cxx_name = "refetchLyrics"]
        fn refetch_lyrics(self: Pin<&mut Library>, track_id: i64);

        /// Mirror player state to MPRIS. `track_json` is a track object or "null".
        #[qinvokable]
        #[cxx_name = "mprisUpdate"]
        fn mpris_update(self: &Library, status: &QString, track_json: &QString, can_next: bool, can_prev: bool, volume: f64);

        #[qinvokable]
        #[cxx_name = "mprisPosition"]
        fn mpris_position(self: &Library, ms: i64, seeked: bool);

        /// Store user-edited lyrics. `synced` = text is LRC. `sidecar` = also write song.lrc/.txt next to the file.
        #[qinvokable]
        #[cxx_name = "saveLyrics"]
        fn save_lyrics(self: Pin<&mut Library>, track_id: i64, text: &QString, synced: bool, sidecar: bool);

        /// Upload the stored lyrics of a track to LRCLIB; answers with `lyricsPublished`.
        #[qinvokable]
        #[cxx_name = "publishLyrics"]
        fn publish_lyrics(self: Pin<&mut Library>, track_id: i64);

        #[qsignal]
        #[cxx_name = "lyricsPublished"]
        fn lyrics_published(self: Pin<&mut Library>, track_id: i64, ok: bool, message: QString);

        /// Small persistent preferences (volume, ReplayGain mode…).
        #[qinvokable]
        #[cxx_name = "setting"]
        fn setting(self: &Library, key: &QString, fallback: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "setSetting"]
        fn set_setting(self: &Library, key: &QString, value: &QString);

        /// Switch the library folder: rescan it and watch it from now on.
        #[qinvokable]
        #[cxx_name = "changeLibraryDir"]
        fn set_library_dir_and_scan(self: Pin<&mut Library>, dir: &QString);

        /// All music folders (JSON array of paths); the first is `libraryDir`.
        #[qinvokable]
        #[cxx_name = "libraryDirsJson"]
        fn library_dirs_json(self: &Library) -> QString;

        #[qinvokable]
        #[cxx_name = "addLibraryDir"]
        fn add_library_dir(self: Pin<&mut Library>, dir: &QString);

        #[qinvokable]
        #[cxx_name = "removeLibraryDir"]
        fn remove_library_dir(self: Pin<&mut Library>, dir: &QString);

        /// Keep the computer awake while music plays (portal Inhibit).
        #[qinvokable]
        #[cxx_name = "setPlaying"]
        fn set_playing(self: Pin<&mut Library>, playing: bool);

        /// Publish the current lyric line on D-Bus for desktop widgets.
        #[qinvokable]
        #[cxx_name = "publishLyricLine"]
        fn publish_lyric_line(self: &Library, line: &QString, next: &QString, title: &QString, artist: &QString);

        /// Import playlists/likes from an export file or folder (Apple Music, YouTube Music, CSV, M3U…).
        /// Runs in the background and answers with importFinished(report JSON).
        #[qinvokable]
        #[cxx_name = "importPath"]
        fn import_path(self: Pin<&mut Library>, path: &QString);

        #[qsignal]
        #[cxx_name = "importFinished"]
        fn import_finished(self: Pin<&mut Library>, report: QString);

        /// Opens the native (portal) file or folder chooser. Answers with pathPicked,
        /// or pickerUnavailable when there's no portal (QML then shows Qt's dialog).
        #[qinvokable]
        #[cxx_name = "pickPath"]
        fn pick_path(self: Pin<&mut Library>, purpose: &QString, title: &QString, directory: bool);

        #[qsignal]
        #[cxx_name = "pathPicked"]
        fn path_picked(self: Pin<&mut Library>, purpose: QString, path: QString);

        #[qsignal]
        #[cxx_name = "pickerUnavailable"]
        fn picker_unavailable(self: Pin<&mut Library>, purpose: QString, directory: bool);

        /// Remote servers (Subsonic/Navidrome, Jellyfin) as JSON.
        #[qinvokable]
        #[cxx_name = "serversJson"]
        fn servers_json(self: &Library) -> QString;

        /// Logs in (in the background), stores the server and syncs it. Answers with serverAdded.
        #[qinvokable]
        #[cxx_name = "addServer"]
        fn add_server(self: Pin<&mut Library>, kind: &QString, url: &QString, user: &QString, password: &QString);

        #[qinvokable]
        #[cxx_name = "removeServer"]
        fn remove_server(self: Pin<&mut Library>, server_id: i64);

        /// Re-sync one server, or all with -1.
        #[qinvokable]
        #[cxx_name = "syncServers"]
        fn sync_servers(self: Pin<&mut Library>, server_id: i64);

        #[qinvokable]
        #[cxx_name = "serverAlbumsJson"]
        fn server_albums_json(self: &Library, server_id: i64) -> QString;

        #[qsignal]
        #[cxx_name = "serverAdded"]
        fn server_added(self: Pin<&mut Library>, ok: bool, message: QString);

        #[qsignal]
        #[cxx_name = "serversChanged"]
        fn servers_changed(self: Pin<&mut Library>);

        #[qsignal]
        #[cxx_name = "libraryChanged"]
        fn library_changed(self: Pin<&mut Library>);

        #[qsignal]
        #[cxx_name = "playlistsChanged"]
        fn playlists_changed(self: Pin<&mut Library>);

        #[qsignal]
        #[cxx_name = "lyricsReady"]
        fn lyrics_ready(self: Pin<&mut Library>, track_id: i64, json: QString);

        /// Search Jamendo + Internet Archive (open licences only); answers with `freeResults`.
        #[qinvokable]
        #[cxx_name = "searchFree"]
        fn search_free(self: Pin<&mut Library>, query: &QString);

        /// `json`: array of tracks; `errors`: array of strings (a source that failed).
        #[qsignal]
        #[cxx_name = "freeResults"]
        fn free_results(self: Pin<&mut Library>, query: QString, json: QString, errors: QString);

        /// Download a free track (FreeTrack JSON) into the library, with its .lrc.
        #[qinvokable]
        #[cxx_name = "downloadFree"]
        fn download_free(self: Pin<&mut Library>, track_json: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "cancelDownload"]
        fn cancel_download(self: &Library, id: &QString);

        /// kind: started | progress | done | here | failed | cancelled. `pct` -1 = unknown size.
        #[qsignal]
        #[cxx_name = "downloadEvent"]
        fn download_event(self: Pin<&mut Library>, id: QString, kind: QString, pct: i32, message: QString);

        /// play, pause, playpause, stop, next, previous, seek (arg = µs offset),
        /// setposition (arg = µs), raise, quit
        #[qsignal]
        #[cxx_name = "mediaCommand"]
        fn media_command(self: Pin<&mut Library>, command: QString, arg: i64);
    }

    impl cxx_qt::Threading for Library {}
}

use crate::desktop::{self, Command, Mpris, TrackMeta};
use arara_core::{covers::CoverCache, db::Db, downloads, freemusic, import, lyrics, remote, scanner, watcher::LibraryWatcher, Paths};
use core::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::json;
use std::path::PathBuf;

pub struct LibraryRust {
    scanning: bool,
    status: QString,
    track_count: i32,
    album_count: i32,
    library_dir: QString,
    dark: bool,
    accent: QString,
    syncing: bool,
    lyrics_progress: QString,
    prefetching: std::sync::Arc<std::sync::atomic::AtomicBool>,
    resolver: remote::Resolver,
    sync_queue: Vec<i64>,
    db_path: PathBuf,
    covers_dir: PathBuf,
    db: Option<Db>,
    rescan_pending: bool,
    watcher: Option<LibraryWatcher>,
    mpris: Option<Mpris>,
    inhibit: Option<desktop::Inhibitor>,
    downloads: Option<downloads::DownloadManager>,
}

impl Default for LibraryRust {
    fn default() -> Self {
        let mut p = Paths::xdg();
        if let Ok(v) = std::env::var("ARARA_DB") {
            p.db = v.into();
        }
        if let Ok(v) = std::env::var("ARARA_COVERS") {
            p.covers = v.into();
        }
        Self {
            scanning: false,
            status: QString::default(),
            track_count: 0,
            album_count: 0,
            library_dir: QString::default(),
            dark: system_prefers_dark(),
            accent: QString::from("#3584e4"),
            syncing: false,
            lyrics_progress: QString::default(),
            prefetching: Default::default(),
            resolver: remote::Resolver::default(),
            sync_queue: Vec::new(),
            db_path: p.db,
            covers_dir: p.covers,
            db: None,
            rescan_pending: false,
            watcher: None,
            mpris: None,
            inhibit: None,
            downloads: None,
        }
    }
}

/// GNOME stores the light/dark preference in GSettings (also exposed via the
/// XDG settings portal). Qt 6.4 can't read it, so we ask once at startup.
fn system_prefers_dark() -> bool {
    if let Ok(v) = std::env::var("ARARA_DARK") {
        return v == "1";
    }
    #[cfg(windows)]
    return desktop::windows_prefers_dark().unwrap_or(false);
    #[cfg(not(windows))]
    std::process::Command::new("gsettings")
        .args(["get", "org.gnome.desktop.interface", "color-scheme"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).contains("dark"))
        .unwrap_or(false)
}

fn default_music_dir() -> String {
    if let Ok(v) = std::env::var("ARARA_LIBRARY") {
        return v;
    }
    #[cfg(windows)]
    return directories::UserDirs::new()
        .and_then(|d| d.audio_dir().map(|p| p.to_string_lossy().into_owned()))
        .unwrap_or_else(|| format!("{}\\Music", std::env::var("USERPROFILE").unwrap_or_default()));
    #[cfg(not(windows))]
    std::process::Command::new("xdg-user-dir")
        .arg("MUSIC")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| format!("{}/Music", std::env::var("HOME").unwrap_or_default()))
}

fn lyrics_to_json(res: lyrics::Lyrics) -> String {
    match res {
        lyrics::Lyrics::Synced(lines) => json!({
            "kind": "synced",
            "lines": lines.iter().map(|l| json!({
                "t": l.start_ms, "e": l.end_ms, "text": l.text, "ws": l.word_synced, "v": l.voice,
                "w": l.words.iter().map(|w| json!([w.start_ms, w.end_ms, w.text])).collect::<Vec<_>>()
            })).collect::<Vec<_>>()
        }),
        lyrics::Lyrics::Plain(p) => json!({ "kind": "plain", "text": p }),
        lyrics::Lyrics::None => json!({ "kind": "none" }),
    }
    .to_string()
}

fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64
}

fn qs(s: &str) -> QString {
    QString::from(s)
}

impl qobject::Library {
    fn refresh_counts(mut self: Pin<&mut Self>) {
        let counts = self.db.as_ref().and_then(|d| d.counts().ok());
        if let Some((t, a, _)) = counts {
            self.as_mut().set_track_count(t as i32);
            self.as_mut().set_album_count(a as i32);
        }
    }

    pub fn open(mut self: Pin<&mut Self>) {
        let db = Db::open(&self.db_path).ok();
        let stored_dir = db.as_ref().and_then(|d| d.get_kv("library_dir").ok().flatten());
        self.as_mut().rust_mut().resolver = db.as_ref().map(remote::Resolver::load).unwrap_or_default();
        self.as_mut().rust_mut().db = db;
        self.as_mut().refresh_counts();
        self.as_mut().library_changed();
        self.as_mut().playlists_changed();

        let dir = stored_dir.unwrap_or_else(default_music_dir);
        self.as_mut().start_scan(&qs(&dir));
        self.as_mut().start_watching(&dir);
        self.as_mut().start_desktop_integration();
        self.as_mut().servers_changed();
        // Remote catalogs are already cached; refresh them in the background
        // (the writer lock makes this wait for the local scan).
        self.as_mut().sync_servers(-1);
    }

    fn start_watching(mut self: Pin<&mut Self>, _dir: &str) {
        let dirs = self.library_dirs();
        self.as_mut().watch_dirs(&dirs);
    }

    fn watch_dirs(mut self: Pin<&mut Self>, dirs: &[String]) {
        let qt = self.qt_thread();
        let roots: Vec<PathBuf> = dirs.iter().map(PathBuf::from).collect();
        let w = LibraryWatcher::new(&roots, std::time::Duration::from_secs(2), move || {
            let _ = qt.queue(|o| o.rescan());
        });
        match w {
            Ok(w) => self.as_mut().rust_mut().watcher = Some(w),
            Err(e) => log::warn!("folder watching unavailable: {e}"),
        }
    }

    fn rescan(mut self: Pin<&mut Self>) {
        if self.scanning {
            self.as_mut().rust_mut().rescan_pending = true;
            return;
        }
        let dir = self.library_dir.clone();
        self.start_scan(&dir);
    }

    fn start_desktop_integration(mut self: Pin<&mut Self>) {
        // Appearance from the portal (falls back to gsettings already read at startup).
        if std::env::var("ARARA_DARK").is_err() {
            let a = desktop::read_appearance();
            if let Some(d) = a.dark {
                self.as_mut().set_dark(d);
            }
            if let Some(hex) = a.accent_hex() {
                self.as_mut().set_accent(qs(&hex));
            }
            let qt = self.qt_thread();
            desktop::watch_appearance(move |a| {
                let _ = qt.queue(move |mut o| {
                    if let Some(d) = a.dark {
                        o.as_mut().set_dark(d);
                    }
                    if let Some(hex) = a.accent_hex() {
                        o.as_mut().set_accent(qs(&hex));
                    }
                });
            });
        }

        let qt = self.qt_thread();
        let m = Mpris::start(move |cmd| {
            let (name, arg) = match cmd {
                Command::Play => ("play", 0),
                Command::Pause => ("pause", 0),
                Command::PlayPause => ("playpause", 0),
                Command::Stop => ("stop", 0),
                Command::Next => ("next", 0),
                Command::Previous => ("previous", 0),
                Command::Seek(us) => ("seek", us),
                Command::SetPosition(us) => ("setposition", us),
                Command::Raise => ("raise", 0),
                Command::Quit => ("quit", 0),
            };
            let _ = qt.queue(move |o| o.media_command(qs(name), arg));
        });
        match m {
            Ok(m) => self.as_mut().rust_mut().mpris = Some(m),
            Err(e) => log::warn!("MPRIS unavailable: {e}"),
        }
    }

    /// Music folders: the primary one plus any added with "Pastas de música".
    fn library_dirs(&self) -> Vec<String> {
        let primary = self.library_dir.to_string();
        let extra: Vec<String> = self
            .db
            .as_ref()
            .and_then(|d| d.get_kv("library_dirs_extra").ok().flatten())
            .and_then(|j| serde_json::from_str(&j).ok())
            .unwrap_or_default();
        let mut out = vec![];
        if !primary.is_empty() {
            out.push(primary);
        }
        for e in extra {
            if !out.contains(&e) {
                out.push(e);
            }
        }
        out
    }

    fn set_extra_dirs(&self, dirs: &[String]) {
        if let Some(d) = &self.db {
            let _ = d.set_kv("library_dirs_extra", &serde_json::to_string(dirs).unwrap());
        }
    }

    pub fn library_dirs_json(&self) -> QString {
        qs(&serde_json::to_string(&self.library_dirs()).unwrap())
    }

    pub fn add_library_dir(mut self: Pin<&mut Self>, dir: &QString) {
        let d = dir.to_string();
        let d = remote::url_to_path(&d).trim_end_matches(['/', '\\']).to_string();
        if d.is_empty() || !std::path::Path::new(&d).is_dir() {
            return;
        }
        let mut dirs = self.library_dirs();
        if dirs.contains(&d) {
            return;
        }
        dirs.push(d);
        self.set_extra_dirs(&dirs[1..]);
        let primary = self.library_dir.clone();
        self.as_mut().rust_mut().rescan_pending = self.scanning;
        if !self.scanning {
            self.as_mut().start_scan(&primary);
        }
        let all = self.library_dirs();
        self.as_mut().watch_dirs(&all);
    }

    pub fn remove_library_dir(mut self: Pin<&mut Self>, dir: &QString) {
        let d = dir.to_string();
        let mut dirs = self.library_dirs();
        dirs.retain(|x| x != &d);
        if dirs.is_empty() {
            return;
        }
        if let Some(db) = &self.db {
            let _ = db.set_kv("library_dir", &dirs[0]);
        }
        self.as_mut().set_library_dir(qs(&dirs[0]));
        self.set_extra_dirs(&dirs[1..]);
        if self.scanning {
            self.as_mut().rust_mut().rescan_pending = true;
        } else {
            let primary = qs(&dirs[0]);
            self.as_mut().start_scan(&primary);
        }
        self.as_mut().watch_dirs(&dirs);
    }

    pub fn set_playing(mut self: Pin<&mut Self>, playing: bool) {
        if playing {
            if self.inhibit.is_none() {
                self.as_mut().rust_mut().inhibit = desktop::Inhibitor::start("Tocando música");
            }
        } else {
            // dropping it releases the inhibition
            self.as_mut().rust_mut().inhibit = None;
        }
    }

    pub fn publish_lyric_line(&self, line: &QString, next: &QString, title: &QString, artist: &QString) {
        if let Some(m) = &self.mpris {
            m.lyric_line(&line.to_string(), &next.to_string(), &title.to_string(), &artist.to_string());
        }
    }

    pub fn start_scan(mut self: Pin<&mut Self>, dir: &QString) {
        if self.scanning {
            return;
        }
        let dir = remote::url_to_path(&dir.to_string());
        if let Some(d) = &self.db {
            let _ = d.set_kv("library_dir", &dir);
        }
        self.as_mut().set_library_dir(qs(&dir));
        let roots: Vec<PathBuf> = self.library_dirs().into_iter().map(PathBuf::from).collect();
        self.as_mut().set_scanning(true);
        self.as_mut().set_status(qs("Procurando músicas…"));

        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        let covers_dir = self.covers_dir.clone();
        std::thread::spawn(move || {
            let result = (|| -> arara_core::Result<scanner::ScanStats> {
                let mut db = Db::open(&db_path)?;
                let covers = CoverCache::new(&covers_dir)?;
                let qt2 = qt.clone();
                scanner::scan(&mut db, &covers, &roots, move |ev| {
                    let msg = match ev {
                        scanner::ScanEvent::Discovered(n) => format!("{n} arquivos encontrados"),
                        scanner::ScanEvent::Parsed { done, total } => format!("Indexando {done}/{total}"),
                        scanner::ScanEvent::Finished(_) => return,
                    };
                    let _ = qt2.queue(move |o| o.set_status(qs(&msg)));
                })
            })();
            let _ = qt.queue(move |mut o| {
                o.as_mut().set_scanning(false);
                match result {
                    Ok(s) => {
                        o.as_mut().set_status(qs(&format!(
                            "{} faixas · {} novas · {} ms",
                            s.seen, s.parsed, s.elapsed_ms
                        )));
                        if s.parsed > 0 || s.removed > 0 {
                            o.as_mut().refresh_counts();
                            o.as_mut().library_changed();
                            o.as_mut().playlists_changed();
                        }
                        o.as_mut().prefetch_lyrics();
                    }
                    Err(e) => o.as_mut().set_status(qs(&format!("Erro: {e}"))),
                }
                if o.rescan_pending {
                    o.as_mut().rust_mut().rescan_pending = false;
                    o.as_mut().rescan();
                }
            });
        });
    }

    fn cover(&self, hash: &Option<String>, size: u32) -> String {
        match hash {
            Some(h) => remote::file_url(&self.covers_dir.join(format!("{h}-{size}.jpg")).to_string_lossy()),
            None => String::new(),
        }
    }

    fn album_value(&self, a: &arara_core::db::AlbumRow) -> serde_json::Value {
        json!({
            "id": a.id, "title": a.title, "artist": a.artist, "artistId": a.artist_id, "year": a.year,
            "tracks": a.track_count, "cover": self.cover(&a.cover_hash, 256),
            "coverBig": self.cover(&a.cover_hash, 640),
        })
    }

    fn track_value(&self, t: &arara_core::db::TrackRow) -> serde_json::Value {
        json!({
            "id": t.id, "title": t.title, "artist": t.artist, "album": t.album,
            "albumId": t.album_id, "duration": t.duration_ms, "starred": t.starred,
            "url": self.resolver.url(&t.path), "remote": remote::is_remote(&t.path),
            "gain": t.track_gain, "albumGain": t.album_gain, "year": t.year, "genre": t.genre,
            "quality": t.quality().0, "qualityDetail": t.quality().1, "explicit": t.explicit,
            "cover": self.cover(&t.cover_hash, 256), "coverBig": self.cover(&t.cover_hash, 640),
        })
    }

    fn tracks_to_json(&self, rows: arara_core::Result<Vec<arara_core::db::TrackRow>>) -> QString {
        let v: Vec<_> = rows.unwrap_or_default().iter().map(|t| self.track_value(t)).collect();
        qs(&serde_json::to_string(&v).unwrap())
    }

    pub fn albums_json(&self) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let v: Vec<_> = db.albums().unwrap_or_default().iter().map(|a| self.album_value(a)).collect();
        qs(&serde_json::to_string(&v).unwrap())
    }

    pub fn artist_albums_json(&self, artist_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let v: Vec<_> = db.artist_albums(artist_id).unwrap_or_default().iter().map(|a| self.album_value(a)).collect();
        qs(&serde_json::to_string(&v).unwrap())
    }

    pub fn artists_json(&self) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let v: Vec<_> = db
            .artists()
            .unwrap_or_default()
            .iter()
            .map(|a| json!({ "id": a.id, "name": a.name, "albums": a.album_count, "cover": self.cover(&a.cover_hash, 256) }))
            .collect();
        qs(&serde_json::to_string(&v).unwrap())
    }

    pub fn album_tracks_json(&self, album_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        self.tracks_to_json(db.album_tracks(album_id))
    }

    pub fn search_json(&self, query: &QString) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        self.tracks_to_json(db.search(&query.to_string(), 200))
    }

    pub fn groups_json(&self, kind: &QString) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let v: Vec<_> = db
            .groups(&kind.to_string())
            .unwrap_or_default()
            .iter()
            .map(|g| json!({ "key": g.key, "name": g.name, "detail": g.detail, "count": g.count,
                             "cover": self.cover(&g.cover_hash, 256), "l": arara_core::query::letter(&g.name) }))
            .collect();
        qs(&serde_json::to_string(&v).unwrap())
    }

    pub fn autoplay_json(&self, seed: i64, exclude_json: &QString, count: i32) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let exclude: std::collections::HashSet<i64> = serde_json::from_str(&exclude_json.to_string()).unwrap_or_default();
        self.tracks_to_json(db.autoplay(seed, &exclude, count.max(1) as usize))
    }

    pub fn cover_blur(&self, url: &QString) -> QString {
        let u = url.to_string();
        let path = &remote::url_to_path(&u);
        if path.is_empty() {
            return qs("");
        }
        match arara_core::covers::blurred(std::path::Path::new(path)) {
            Some(p) => qs(&remote::file_url(&p.to_string_lossy())),
            None => qs(""),
        }
    }

    pub fn cover_colors(&self, url: &QString) -> QString {
        let u = url.to_string();
        let path = &remote::url_to_path(&u);
        qs(&serde_json::to_string(&arara_core::covers::palette(std::path::Path::new(path))).unwrap())
    }

    pub fn starred_json(&self) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        self.tracks_to_json(db.starred_tracks())
    }

    pub fn recent_json(&self) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        self.tracks_to_json(db.recent_tracks(50))
    }

    pub fn most_played_json(&self) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        self.tracks_to_json(db.most_played(50))
    }

    pub fn set_starred(self: Pin<&mut Self>, track_id: i64, starred: bool) -> bool {
        match &self.db {
            Some(db) if db.set_starred(track_id, starred).is_ok() => starred,
            _ => !starred,
        }
    }

    pub fn set_explicit(self: Pin<&mut Self>, track_id: i64, mode: i32) -> i32 {
        if let Some(db) = &self.db {
            let v = match mode { 1 => Some(true), 0 => Some(false), _ => None };
            let _ = db.set_explicit_user(track_id, v);
        }
        self.explicit_of(track_id)
    }

    pub fn explicit_of(&self, track_id: i64) -> i32 {
        let Some(db) = &self.db else { return 0 };
        db.track(track_id).ok().flatten().map(|t| t.explicit as i32).unwrap_or(0)
    }

    pub fn record_play(&self, track_id: i64) {
        if let Some(db) = &self.db {
            let _ = db.record_play(track_id, now());
        }
    }

    pub fn playlists_json(&self) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let v: Vec<_> = db
            .playlists()
            .unwrap_or_default()
            .iter()
            .map(|p| json!({ "id": p.id, "name": p.name, "tracks": p.track_count, "cover": self.cover(&p.cover_hash, 256),
                             "smart": p.smart.is_some(), "query": p.smart.as_ref().map(|s| s.0.clone()),
                             "sort": p.smart.as_ref().map(|s| s.1.clone()), "limit": p.smart.as_ref().map(|s| s.2) }))
            .collect();
        qs(&serde_json::to_string(&v).unwrap())
    }

    pub fn playlist_tracks_json(&self, playlist_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        self.tracks_to_json(db.playlist_tracks(playlist_id))
    }

    pub fn create_playlist(mut self: Pin<&mut Self>, name: &QString) -> i64 {
        let id = self.db.as_ref().and_then(|db| db.create_playlist(&name.to_string()).ok()).unwrap_or(-1);
        self.as_mut().playlists_changed();
        id
    }

    pub fn save_smart_playlist(mut self: Pin<&mut Self>, id: i64, name: &QString, query: &QString, sort: &QString, limit: i64) -> i64 {
        let id = self
            .db
            .as_ref()
            .and_then(|db| {
                db.save_smart_playlist((id >= 0).then_some(id), &name.to_string(), &query.to_string(), &sort.to_string(), limit.max(0)).ok()
            })
            .unwrap_or(-1);
        self.as_mut().playlists_changed();
        id
    }

    pub fn rename_playlist(mut self: Pin<&mut Self>, playlist_id: i64, name: &QString) {
        if let Some(db) = &self.db {
            let _ = db.rename_playlist(playlist_id, &name.to_string());
        }
        self.as_mut().playlists_changed();
    }

    pub fn delete_playlist(mut self: Pin<&mut Self>, playlist_id: i64) {
        if let Some(db) = &self.db {
            let _ = db.delete_playlist(playlist_id);
        }
        self.as_mut().playlists_changed();
    }

    pub fn add_to_playlist(mut self: Pin<&mut Self>, playlist_id: i64, track_ids_json: &QString) {
        let ids: Vec<i64> = serde_json::from_str(&track_ids_json.to_string()).unwrap_or_default();
        if let Some(db) = &self.db {
            let _ = db.add_to_playlist(playlist_id, &ids);
        }
        self.as_mut().playlists_changed();
    }

    pub fn move_in_playlist(mut self: Pin<&mut Self>, playlist_id: i64, from: i64, to: i64) {
        if let Some(db) = &self.db {
            let _ = db.move_in_playlist(playlist_id, from, to);
        }
        self.as_mut().playlists_changed();
    }

    pub fn remove_from_playlist(mut self: Pin<&mut Self>, playlist_id: i64, pos: i64) {
        if let Some(db) = &self.db {
            let _ = db.remove_from_playlist(playlist_id, pos);
        }
        self.as_mut().playlists_changed();
    }

    pub fn save_queue(&self, json: &QString) {
        if let Some(db) = &self.db {
            let _ = db.set_kv("queue", &json.to_string());
        }
    }

    pub fn load_queue(&self) -> QString {
        let Some(db) = &self.db else { return qs("null") };
        let Some(raw) = db.get_kv("queue").ok().flatten() else { return qs("null") };
        let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) else { return qs("null") };
        let ids: Vec<i64> = v["ids"].as_array().map(|a| a.iter().filter_map(|x| x.as_i64()).collect()).unwrap_or_default();
        let index = v["index"].as_i64().unwrap_or(0);
        let current = ids.get(index as usize).copied();
        // Tracks may have been deleted since; keep the current one pointed at correctly.
        let tracks = db.tracks_by_ids(&ids).unwrap_or_default();
        let new_index = current.and_then(|c| tracks.iter().position(|t| t.id == c)).unwrap_or(0);
        let out = json!({
            "tracks": tracks.iter().map(|t| self.track_value(t)).collect::<Vec<_>>(),
            "index": new_index,
            "repeat": v["repeat"].as_str().unwrap_or("off"),
            "pos": if current.is_some() && tracks.get(new_index).map(|t| Some(t.id) == current).unwrap_or(false) { v["pos"].as_i64().unwrap_or(0) } else { 0 },
        });
        qs(&out.to_string())
    }

    pub fn refetch_lyrics(self: Pin<&mut Self>, track_id: i64) {
        if let Some(db) = self.db.as_ref() {
            let _ = db.conn.execute("DELETE FROM lyrics WHERE track_id=?1", [track_id]);
        }
        self.request_lyrics(track_id);
    }

    pub fn request_lyrics(self: Pin<&mut Self>, track_id: i64) {
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        std::thread::spawn(move || {
            let online = std::env::var("ARARA_OFFLINE").is_err();
            let client = online.then(lyrics::LrclibClient::default);
            let res = Db::open(&db_path)
                .ok()
                .and_then(|db| lyrics::resolve(&db, client.as_ref(), track_id).ok())
                .unwrap_or(lyrics::Lyrics::None);
            let s = lyrics_to_json(res);
            let _ = qt.queue(move |o| o.lyrics_ready(track_id, qs(&s)));
        });
    }

    pub fn save_lyrics(mut self: Pin<&mut Self>, track_id: i64, text: &QString, synced: bool, sidecar: bool) {
        let text = text.to_string();
        let Some(db) = &self.db else { return };
        let (s, p) = if synced { (Some(text.as_str()), None) } else { (None, Some(text.as_str())) };
        let _ = db.store_lyrics(track_id, "user", s, p, now());
        if sidecar {
            if let Ok(Some(t)) = db.track(track_id).map(|t| t.filter(|t| !remote::is_remote(&t.path))) {
                let ext = if synced { "lrc" } else { "txt" };
                if let Err(e) = std::fs::write(std::path::Path::new(&t.path).with_extension(ext), &text) {
                    log::warn!("could not write sidecar lyrics: {e}");
                }
            }
        }
        let dur = db.track(track_id).ok().flatten().map(|t| t.duration_ms as u64);
        let res = if synced {
            lyrics::Lyrics::Synced(lyrics::parse_lrc(&text, dur))
        } else if text.trim().is_empty() {
            lyrics::Lyrics::None
        } else {
            lyrics::Lyrics::Plain(text.clone())
        };
        let json = lyrics_to_json(res);
        self.as_mut().lyrics_ready(track_id, qs(&json));
    }

    pub fn publish_lyrics(self: Pin<&mut Self>, track_id: i64) {
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        std::thread::spawn(move || {
            let result = (|| -> Result<(), String> {
                let db = Db::open(&db_path).map_err(|e| e.to_string())?;
                let t = db.track(track_id).map_err(|e| e.to_string())?.ok_or("faixa não encontrada")?;
                let (_, synced, plain) = db.cached_lyrics(track_id).map_err(|e| e.to_string())?.ok_or("sem letra salva")?;
                let synced = synced.unwrap_or_default();
                let plain = plain.unwrap_or_else(|| lyrics::lrc_to_plain(&synced));
                lyrics::LrclibClient::default().publish(&lyrics::PublishRequest {
                    track_name: t.title,
                    artist_name: t.artist,
                    album_name: t.album.unwrap_or_default(),
                    duration: (t.duration_ms as u64 + 500) / 1000,
                    plain_lyrics: plain,
                    synced_lyrics: synced,
                })
            })();
            let (ok, msg) = match result {
                Ok(()) => (true, "Letra enviada ao LRCLIB. Obrigado!".to_string()),
                Err(e) => (false, format!("Não foi possível enviar: {e}")),
            };
            let _ = qt.queue(move |o| o.lyrics_published(track_id, ok, qs(&msg)));
        });
    }

    pub fn mpris_update(&self, status: &QString, track_json: &QString, can_next: bool, can_prev: bool, volume: f64) {
        let Some(m) = &self.mpris else { return };
        let v: serde_json::Value = serde_json::from_str(&track_json.to_string()).unwrap_or(serde_json::Value::Null);
        let meta = v.as_object().map(|t| TrackMeta {
            id: t.get("id").and_then(|x| x.as_i64()).unwrap_or(0),
            title: t.get("title").and_then(|x| x.as_str()).unwrap_or_default().into(),
            artist: t.get("artist").and_then(|x| x.as_str()).unwrap_or_default().into(),
            album: t.get("album").and_then(|x| x.as_str()).unwrap_or_default().into(),
            art_url: t.get("coverBig").and_then(|x| x.as_str()).unwrap_or_default().into(),
            length_us: t.get("duration").and_then(|x| x.as_i64()).unwrap_or(0) * 1000,
        });
        m.update(&status.to_string(), meta, can_next, can_prev, volume);
    }

    pub fn mpris_position(&self, ms: i64, seeked: bool) {
        if let Some(m) = &self.mpris {
            if seeked {
                m.seeked(ms * 1000)
            } else {
                m.set_position(ms * 1000)
            }
        }
    }
}

// ---------- remote servers ----------
impl qobject::Library {
    pub fn servers_json(&self) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let v: Vec<_> = remote::servers(db)
            .unwrap_or_default()
            .iter()
            .map(|s| {
                json!({
                    "id": s.id, "kind": s.kind.as_str(), "name": s.name, "url": s.url, "user": s.username,
                    "tracks": s.track_count, "lastSync": s.last_sync, "error": s.last_error,
                })
            })
            .collect();
        qs(&serde_json::to_string(&v).unwrap())
    }

    pub fn server_albums_json(&self, server_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let v: Vec<_> = remote::server_albums(db, server_id).unwrap_or_default().iter().map(|a| self.album_value(a)).collect();
        qs(&serde_json::to_string(&v).unwrap())
    }

    pub fn add_server(self: Pin<&mut Self>, kind: &QString, url: &QString, user: &QString, password: &QString) {
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        let (kind, url, user, password) = (kind.to_string(), url.to_string(), user.to_string(), password.to_string());
        std::thread::spawn(move || {
            let res = (|| -> Result<(i64, String), String> {
                let kind = remote::Kind::parse(&kind).ok_or("tipo de servidor desconhecido")?;
                if url.trim().is_empty() {
                    return Err("informe o endereço do servidor".into());
                }
                let (url, auth, name) = remote::login(kind, &url, &user, &password)?;
                let db = Db::open(&db_path).map_err(|e| e.to_string())?;
                let id = remote::add_server(&db, kind, &name, &url, &user, &auth).map_err(|e| e.to_string())?;
                Ok((id, name))
            })();
            let _ = qt.queue(move |mut o| match res {
                Ok((id, name)) => {
                    o.as_mut().reload_resolver();
                    o.as_mut().servers_changed();
                    o.as_mut().server_added(true, qs(&format!("Conectado a “{name}”. Sincronizando…")));
                    o.as_mut().sync_servers(id);
                }
                Err(e) => o.as_mut().server_added(false, qs(&e)),
            });
        });
    }

    pub fn remove_server(mut self: Pin<&mut Self>, server_id: i64) {
        let db_path = self.db_path.clone();
        let removed = Db::open(&db_path).and_then(|mut db| remote::remove_server(&mut db, server_id));
        if let Err(e) = removed {
            self.as_mut().set_status(qs(&format!("Erro ao remover servidor: {e}")));
        }
        self.as_mut().reload_resolver();
        self.as_mut().refresh_counts();
        self.as_mut().servers_changed();
        self.as_mut().library_changed();
        self.as_mut().playlists_changed();
    }

    fn reload_resolver(mut self: Pin<&mut Self>) {
        let r = self.db.as_ref().map(remote::Resolver::load).unwrap_or_default();
        self.as_mut().rust_mut().resolver = r;
    }

    pub fn sync_servers(mut self: Pin<&mut Self>, server_id: i64) {
        let ids: Vec<i64> = match &self.db {
            Some(db) => remote::servers(db)
                .unwrap_or_default()
                .into_iter()
                .map(|s| s.id)
                .filter(|id| server_id < 0 || *id == server_id)
                .collect(),
            None => return,
        };
        for id in ids {
            if !self.sync_queue.contains(&id) {
                self.as_mut().rust_mut().sync_queue.push(id);
            }
        }
        if !self.syncing {
            self.as_mut().sync_next();
        }
    }

    /// Syncs queued servers one at a time on a worker thread.
    fn sync_next(mut self: Pin<&mut Self>) {
        if self.sync_queue.is_empty() {
            self.as_mut().set_syncing(false);
            return;
        }
        let id = self.as_mut().rust_mut().sync_queue.remove(0);
        self.as_mut().set_syncing(true);
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        let covers_dir = self.covers_dir.clone();
        std::thread::spawn(move || {
            let res = (|| -> Result<(String, remote::SyncStats), (Option<String>, String)> {
                let mut db = Db::open(&db_path).map_err(|e| (None, e.to_string()))?;
                let covers = CoverCache::new(&covers_dir).map_err(|e| (None, e.to_string()))?;
                let server = remote::server(&db, id).ok().flatten().ok_or((None, "servidor removido".to_string()))?;
                let qt2 = qt.clone();
                let stats = remote::sync(&mut db, &covers, &server, move |m| {
                    let _ = qt2.queue(move |o| o.set_status(qs(&m)));
                })
                .map_err(|e| {
                    let _ = remote::set_error(&db, id, Some(&e));
                    (Some(server.name.clone()), e)
                })?;
                Ok((server.name, stats))
            })();
            let _ = qt.queue(move |mut o| {
                match res {
                    Ok((name, s)) => {
                        o.as_mut().set_status(qs(&format!("{name}: {} faixas · {} ms", s.tracks, s.elapsed_ms)));
                        if s.written > 0 || s.removed > 0 || s.covers > 0 {
                            o.as_mut().refresh_counts();
                            o.as_mut().library_changed();
                            o.as_mut().playlists_changed();
                        }
                    }
                    Err((name, e)) => {
                        let who = name.map(|n| format!("{n}: ")).unwrap_or_default();
                        o.as_mut().set_status(qs(&format!("{who}{e}")));
                    }
                }
                o.as_mut().servers_changed();
                o.as_mut().sync_next();
                o.as_mut().prefetch_lyrics();
            });
        });
    }
}

// ---------- preferences ----------
impl qobject::Library {
    pub fn setting(&self, key: &QString, fallback: &QString) -> QString {
        let v = self.db.as_ref().and_then(|d| d.get_kv(&format!("pref:{key}")).ok().flatten());
        v.map(|s| qs(&s)).unwrap_or_else(|| fallback.clone())
    }

    pub fn set_setting(&self, key: &QString, value: &QString) {
        if let Some(d) = &self.db {
            let _ = d.set_kv(&format!("pref:{key}"), &value.to_string());
        }
    }

    pub fn set_library_dir_and_scan(mut self: Pin<&mut Self>, dir: &QString) {
        let d = dir.to_string();
        let d = remote::url_to_path(&d);
        if d.is_empty() || !std::path::Path::new(&d).is_dir() {
            self.as_mut().set_status(qs("Pasta inválida"));
            return;
        }
        self.as_mut().start_scan(&qs(&d));
        self.as_mut().start_watching(&d);
    }
}

// ---------- import from streaming services ----------
impl qobject::Library {
    pub fn import_path(self: Pin<&mut Self>, path: &QString) {
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        let p = path.to_string();
        let p = PathBuf::from(remote::url_to_path(&p));
        std::thread::spawn(move || {
            let out = (|| -> Result<import::Report, String> {
                let pls = import::read_path(&p)?;
                if pls.is_empty() {
                    return Err("nenhuma playlist reconhecida nesse arquivo ou pasta".into());
                }
                let db = Db::open(&db_path).map_err(|e| e.to_string())?;
                import::apply(&db, &pls).map_err(|e| e.to_string())
            })();
            let json = match out {
                Ok(r) => serde_json::to_value(&r).map(|mut v| { v["ok"] = true.into(); v }).unwrap_or_default().to_string(),
                Err(e) => json!({ "ok": false, "error": e }).to_string(),
            };
            let _ = qt.queue(move |mut o| {
                o.as_mut().playlists_changed();
                o.as_mut().library_changed();
                o.as_mut().import_finished(qs(&json));
            });
        });
    }
}

impl qobject::Library {
    pub fn pick_path(self: Pin<&mut Self>, purpose: &QString, title: &QString, directory: bool) {
        let qt = self.qt_thread();
        let (purpose, title) = (purpose.to_string(), title.to_string());
        std::thread::spawn(move || {
            const EXPORTS: &[&str] = &["*.xml", "*.csv", "*.json", "*.m3u", "*.m3u8", "*.xspf"];
            let filters: &[(&str, &[&str])] = if directory { &[] } else { &[("Exportações de playlists", EXPORTS), ("Todos os arquivos", &["*"])] };
            let res = desktop::portal_pick(&title, directory, filters);
            let _ = qt.queue(move |mut o| match res {
                Ok(Some(p)) => o.as_mut().path_picked(qs(&purpose), qs(&p)),
                Ok(None) => {}
                Err(e) => {
                    log::info!("file chooser portal unavailable ({e}); using Qt's dialog");
                    o.as_mut().picker_unavailable(qs(&purpose), directory)
                }
            });
        });
    }
}

// ---------- background lyrics download ----------
impl qobject::Library {
    pub fn search_free(self: Pin<&mut Self>, query: &QString) {
        let q = query.to_string();
        let key = self.db.as_ref().and_then(|d| d.get_kv("pref:jamendo").ok().flatten()).or_else(|| std::env::var("ARARA_JAMENDO_CLIENT_ID").ok());
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let (tracks, errors) = freemusic::FreeMusic::default().search(&q, key.as_deref());
            let json = serde_json::to_string(&tracks).unwrap_or_else(|_| "[]".into());
            let errs = serde_json::to_string(&errors).unwrap_or_else(|_| "[]".into());
            let _ = qt.queue(move |o| o.free_results(qs(&q), qs(&json), qs(&errs)));
        });
    }

    pub fn download_free(mut self: Pin<&mut Self>, track_json: &QString) -> bool {
        let Ok(t) = serde_json::from_str::<serde_json::Value>(&track_json.to_string()) else { return false };
        let g = |k: &str| t[k].as_str().unwrap_or("").to_string();
        if g("download_url").is_empty() {
            return false;
        }
        if self.downloads.is_none() {
            let qt = self.qt_thread();
            let workers = self.db.as_ref()
                .and_then(|d| d.get_kv("pref:dlworkers").ok().flatten())
                .and_then(|v| v.parse::<f64>().ok())
                .map(|n| n.clamp(1.0, 4.0) as usize)
                .unwrap_or(2);
            let mgr = downloads::DownloadManager::new(workers, move |ev| {
                use downloads::DownloadEvent as E;
                let (id, kind, pct, msg) = match ev {
                    E::Started { id } => (id, "started", 0, String::new()),
                    E::Progress { id, done, total } => (id, "progress", if total > 0 { (done * 100 / total) as i32 } else { -1 }, String::new()),
                    E::AlreadyHere { id, path } => (id, "here", 100, path.display().to_string()),
                    E::Finished { id, path, lyrics } => (id, "done", 100, format!("{}{}", path.display(), if lyrics { "|lrc" } else { "" })),
                    E::Failed { id, error } => (id, "failed", 0, error),
                    E::Cancelled { id } => (id, "cancelled", 0, String::new()),
                };
                let finished = kind == "done";
                let _ = qt.queue(move |mut o| {
                    o.as_mut().download_event(qs(&id), qs(kind), pct, qs(&msg));
                    // the new file is in a watched folder; index it now so it shows up at once
                    if finished {
                        o.as_mut().rescan();
                    }
                });
            });
            self.as_mut().rust_mut().downloads = Some(mgr);
        }
        let root = PathBuf::from(self.library_dir.to_string()).join("Música livre");
        let dest = downloads::library_path(&root, &g("artist"), &g("album"), &g("title"), &g("ext"));
        let task = downloads::DownloadTask {
            id: g("id"),
            url: g("download_url"),
            dest,
            artist: g("artist"),
            title: g("title"),
            album: g("album"),
            duration_s: t["duration_ms"].as_u64().unwrap_or(0) / 1000,
            lyrics: std::env::var("ARARA_OFFLINE").is_err(),
            comment: format!("{} · {} · {}", g("license"), g("source"), g("page_url")),
        };
        self.downloads.as_ref().map(|m| m.enqueue(task)).unwrap_or(false)
    }

    pub fn cancel_download(&self, id: &QString) {
        if let Some(m) = &self.downloads {
            m.cancel(&id.to_string());
        }
    }

    /// After indexing: look up lyrics (sidecar, tags, LRCLIB) for every track that has none yet,
    /// most-played first, two requests at a time. One run at a time; stops when offline.
    pub fn prefetch_lyrics(mut self: Pin<&mut Self>) {
        use std::sync::atomic::{AtomicUsize, Ordering};
        if std::env::var("ARARA_OFFLINE").is_ok() {
            return;
        }
        if self.db.as_ref().and_then(|d| d.get_kv("pref:autolyrics").ok().flatten()).as_deref() == Some("0") {
            return;
        }
        let running = self.prefetching.clone();
        if running.swap(true, Ordering::SeqCst) {
            return;
        }
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        self.as_mut().set_lyrics_progress(QString::default());
        std::thread::spawn(move || {
            let ids = Db::open(&db_path).and_then(|db| lyrics::pending_tracks(&db)).unwrap_or_default();
            let total = ids.len();
            let next = AtomicUsize::new(0);
            let done = AtomicUsize::new(0);
            let found = AtomicUsize::new(0);
            let net_fail = AtomicUsize::new(0);
            std::thread::scope(|sc| {
                for _ in 0..2 {
                    sc.spawn(|| {
                        let Ok(db) = Db::open(&db_path) else { return };
                        let client = lyrics::LrclibClient::default();
                        loop {
                            let i = next.fetch_add(1, Ordering::SeqCst);
                            if i >= total || net_fail.load(Ordering::SeqCst) >= 15 {
                                return;
                            }
                            let id = ids[i];
                            let before = db.cached_lyrics(id).ok().flatten().is_some();
                            let res = lyrics::resolve(&db, Some(&client), id).unwrap_or(lyrics::Lyrics::None);
                            let stored = db.cached_lyrics(id).ok().flatten().is_some();
                            // nothing stored and nothing found: LRCLIB was unreachable
                            if !stored && !before {
                                net_fail.fetch_add(1, Ordering::SeqCst);
                            } else {
                                net_fail.store(0, Ordering::SeqCst);
                            }
                            let n = done.fetch_add(1, Ordering::SeqCst) + 1;
                            if !matches!(res, lyrics::Lyrics::None) {
                                found.fetch_add(1, Ordering::SeqCst);
                                let json = lyrics_to_json(res);
                                let _ = qt.queue(move |o| o.lyrics_ready(id, qs(&json)));
                            }
                            if n % 10 == 0 || n == total {
                                let msg = format!("Baixando letras {n} de {total}");
                                let _ = qt.queue(move |o| o.set_lyrics_progress(qs(&msg)));
                            }
                        }
                    });
                }
            });
            running.store(false, Ordering::SeqCst);
            let offline = net_fail.load(Ordering::SeqCst) >= 15;
            let f = found.load(Ordering::SeqCst);
            log::info!("lyrics prefetch: {f} found of {total}{}", if offline { " (stopped: offline)" } else { "" });
            let _ = qt.queue(|o| o.set_lyrics_progress(QString::default()));
        });
    }
}
