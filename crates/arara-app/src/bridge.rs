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

        /// Mirror player state to MPRIS. `track_json` is a track object or "null".
        #[qinvokable]
        #[cxx_name = "mprisUpdate"]
        fn mpris_update(self: &Library, status: &QString, track_json: &QString, can_next: bool, can_prev: bool, volume: f64);

        #[qinvokable]
        #[cxx_name = "mprisPosition"]
        fn mpris_position(self: &Library, ms: i64, seeked: bool);

        #[qsignal]
        #[cxx_name = "libraryChanged"]
        fn library_changed(self: Pin<&mut Library>);

        #[qsignal]
        #[cxx_name = "playlistsChanged"]
        fn playlists_changed(self: Pin<&mut Library>);

        #[qsignal]
        #[cxx_name = "lyricsReady"]
        fn lyrics_ready(self: Pin<&mut Library>, track_id: i64, json: QString);

        /// play, pause, playpause, stop, next, previous, seek (arg = µs offset),
        /// setposition (arg = µs), raise, quit
        #[qsignal]
        #[cxx_name = "mediaCommand"]
        fn media_command(self: Pin<&mut Library>, command: QString, arg: i64);
    }

    impl cxx_qt::Threading for Library {}
}

use crate::desktop::{self, Command, Mpris, TrackMeta};
use arara_core::{covers::CoverCache, db::Db, lyrics, scanner, watcher::LibraryWatcher, Paths};
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
    db_path: PathBuf,
    covers_dir: PathBuf,
    db: Option<Db>,
    rescan_pending: bool,
    watcher: Option<LibraryWatcher>,
    mpris: Option<Mpris>,
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
            db_path: p.db,
            covers_dir: p.covers,
            db: None,
            rescan_pending: false,
            watcher: None,
            mpris: None,
        }
    }
}

/// GNOME stores the light/dark preference in GSettings (also exposed via the
/// XDG settings portal). Qt 6.4 can't read it, so we ask once at startup.
fn system_prefers_dark() -> bool {
    if let Ok(v) = std::env::var("ARARA_DARK") {
        return v == "1";
    }
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
    std::process::Command::new("xdg-user-dir")
        .arg("MUSIC")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| format!("{}/Music", std::env::var("HOME").unwrap_or_default()))
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
        self.as_mut().rust_mut().db = db;
        self.as_mut().refresh_counts();
        self.as_mut().library_changed();
        self.as_mut().playlists_changed();

        let dir = stored_dir.unwrap_or_else(default_music_dir);
        self.as_mut().start_scan(&qs(&dir));
        self.as_mut().start_watching(&dir);
        self.as_mut().start_desktop_integration();
    }

    fn start_watching(mut self: Pin<&mut Self>, dir: &str) {
        let qt = self.qt_thread();
        let w = LibraryWatcher::new(&[PathBuf::from(dir)], std::time::Duration::from_secs(2), move || {
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

    pub fn start_scan(mut self: Pin<&mut Self>, dir: &QString) {
        if self.scanning {
            return;
        }
        let dir = dir.to_string().trim_start_matches("file://").to_string();
        if let Some(d) = &self.db {
            let _ = d.set_kv("library_dir", &dir);
        }
        self.as_mut().set_library_dir(qs(&dir));
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
                scanner::scan(&mut db, &covers, &[PathBuf::from(&dir)], move |ev| {
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
            Some(h) => format!("file://{}/{h}-{size}.jpg", self.covers_dir.display()),
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
            "url": format!("file://{}", t.path),
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
            .map(|p| json!({ "id": p.id, "name": p.name, "tracks": p.track_count, "cover": self.cover(&p.cover_hash, 256) }))
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
            let v = match res {
                lyrics::Lyrics::Synced(lines) => json!({
                    "kind": "synced",
                    "lines": lines.iter().map(|l| json!({
                        "t": l.start_ms, "e": l.end_ms, "text": l.text, "ws": l.word_synced,
                        "w": l.words.iter().map(|w| json!([w.start_ms, w.end_ms, w.text])).collect::<Vec<_>>()
                    })).collect::<Vec<_>>()
                }),
                lyrics::Lyrics::Plain(p) => json!({ "kind": "plain", "text": p }),
                lyrics::Lyrics::None => json!({ "kind": "none" }),
            };
            let s = v.to_string();
            let _ = qt.queue(move |o| o.lyrics_ready(track_id, qs(&s)));
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
