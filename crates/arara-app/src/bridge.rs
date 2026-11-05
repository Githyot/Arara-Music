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
        type Library = super::LibraryRust;

        /// Opens the cached index (instant) and starts a background rescan.
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
        #[cxx_name = "searchJson"]
        fn search_json(self: &Library, query: &QString) -> QString;

        /// Resolves lyrics on a worker thread; answers with `lyricsReady`.
        #[qinvokable]
        #[cxx_name = "requestLyrics"]
        fn request_lyrics(self: Pin<&mut Library>, track_id: i64);

        #[qsignal]
        #[cxx_name = "libraryChanged"]
        fn library_changed(self: Pin<&mut Library>);

        #[qsignal]
        #[cxx_name = "lyricsReady"]
        fn lyrics_ready(self: Pin<&mut Library>, track_id: i64, json: QString);
    }

    impl cxx_qt::Threading for Library {}
}

use arara_core::{covers::CoverCache, db::Db, lyrics, scanner, Paths};
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
    db_path: PathBuf,
    covers_dir: PathBuf,
    db: Option<Db>,
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
            db_path: p.db,
            covers_dir: p.covers,
            db: None,
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
        let stored_dir = db.as_ref().and_then(|d| {
            d.conn
                .query_row("SELECT v FROM kv WHERE k='library_dir'", [], |r| r.get::<_, String>(0))
                .ok()
        });
        self.as_mut().rust_mut().db = db;
        self.as_mut().refresh_counts();
        self.as_mut().library_changed();

        let dir = stored_dir.unwrap_or_else(default_music_dir);
        self.as_mut().start_scan(&QString::from(dir.as_str()));
    }

    pub fn start_scan(mut self: Pin<&mut Self>, dir: &QString) {
        if self.scanning {
            return;
        }
        let dir = dir.to_string().trim_start_matches("file://").to_string();
        if let Some(d) = &self.db {
            let _ = d.conn.execute(
                "INSERT INTO kv(k,v) VALUES('library_dir',?1) ON CONFLICT(k) DO UPDATE SET v=excluded.v",
                [&dir],
            );
        }
        self.as_mut().set_library_dir(QString::from(dir.as_str()));
        self.as_mut().set_scanning(true);
        self.as_mut().set_status(QString::from("Procurando músicas…"));

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
                    let _ = qt2.queue(move |o| o.set_status(QString::from(msg.as_str())));
                })
            })();
            let _ = qt.queue(move |mut o| {
                o.as_mut().set_scanning(false);
                match result {
                    Ok(s) => {
                        o.as_mut().set_status(QString::from(
                            format!("{} faixas · {} novas · {} ms", s.seen, s.parsed, s.elapsed_ms).as_str(),
                        ));
                        if s.parsed > 0 || s.removed > 0 {
                            o.as_mut().refresh_counts();
                            o.as_mut().library_changed();
                        }
                    }
                    Err(e) => o.as_mut().set_status(QString::from(format!("Erro: {e}").as_str())),
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

    pub fn albums_json(&self) -> QString {
        let Some(db) = &self.db else { return QString::from("[]") };
        let rows = db.albums().unwrap_or_default();
        let v: Vec<_> = rows
            .iter()
            .map(|a| {
                json!({
                    "id": a.id, "title": a.title, "artist": a.artist, "year": a.year,
                    "tracks": a.track_count, "cover": self.cover(&a.cover_hash, 256),
                    "coverBig": self.cover(&a.cover_hash, 640),
                })
            })
            .collect();
        QString::from(serde_json::to_string(&v).unwrap().as_str())
    }

    fn tracks_to_json(&self, rows: Vec<arara_core::db::TrackRow>) -> QString {
        let db = self.db.as_ref().unwrap();
        let v: Vec<_> = rows
            .into_iter()
            .map(|t| {
                let hash: Option<String> = t.album_id.and_then(|id| {
                    db.conn
                        .query_row("SELECT cover_hash FROM albums WHERE id=?1", [id], |r| r.get(0))
                        .ok()
                        .flatten()
                });
                json!({
                    "id": t.id, "title": t.title, "artist": t.artist, "album": t.album,
                    "albumId": t.album_id, "duration": t.duration_ms,
                    "url": format!("file://{}", t.path),
                    "cover": self.cover(&hash, 256), "coverBig": self.cover(&hash, 640),
                })
            })
            .collect();
        QString::from(serde_json::to_string(&v).unwrap().as_str())
    }

    pub fn album_tracks_json(&self, album_id: i64) -> QString {
        let Some(db) = &self.db else { return QString::from("[]") };
        self.tracks_to_json(db.album_tracks(album_id).unwrap_or_default())
    }

    pub fn search_json(&self, query: &QString) -> QString {
        let Some(db) = &self.db else { return QString::from("[]") };
        self.tracks_to_json(db.search(&query.to_string(), 200).unwrap_or_default())
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
            let _ = qt.queue(move |o| o.lyrics_ready(track_id, QString::from(s.as_str())));
        });
    }
}
