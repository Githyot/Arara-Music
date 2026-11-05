//! Native list models (QAbstractListModel implemented in Rust).
//!
//! Rows stay as compact Rust structs; QML only asks for the roles of the
//! delegates on screen. This keeps "all songs" usable at 50k+ tracks
//! without building tens of thousands of JS objects.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(<QtCore/QAbstractListModel>);
        type QAbstractListModel;

        include!("cxx-qt-lib/qhash.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QAbstractListModel]
        #[qproperty(i32, count)]
        type TrackModel = super::TrackModelRust;

        /// Every track, sorted by artist, album, disc, track.
        #[qinvokable]
        #[cxx_name = "loadAll"]
        fn load_all(self: Pin<&mut TrackModel>);

        #[qinvokable]
        fn search(self: Pin<&mut TrackModel>, query: &QString);

        /// JSON array of track objects for rows [from, from+count) — used to build a play queue.
        #[qinvokable]
        #[cxx_name = "sliceJson"]
        fn slice_json(self: &TrackModel, from: i32, count: i32) -> QString;

        #[qinvokable]
        #[cxx_name = "setStarredAt"]
        fn set_starred_at(self: Pin<&mut TrackModel>, row: i32, starred: bool);

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut TrackModel>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut TrackModel>);

        #[cxx_override]
        fn data(self: &TrackModel, index: &QModelIndex, role: i32) -> QVariant;

        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &TrackModel) -> QHash_i32_QByteArray;

        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &TrackModel, parent: &QModelIndex) -> i32;
    }
}

use arara_core::db::{Db, TrackRow};
use arara_core::{remote, Paths};
use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};
use std::path::PathBuf;

const ROLES: &[&str] = &["trackId", "title", "artist", "album", "albumId", "duration", "starred", "cover", "coverBig", "url", "remote"];

pub struct TrackModelRust {
    count: i32,
    rows: Vec<TrackRow>,
    db_path: PathBuf,
    covers_dir: PathBuf,
    resolver: remote::Resolver,
}

impl Default for TrackModelRust {
    fn default() -> Self {
        let mut p = Paths::xdg();
        if let Ok(v) = std::env::var("ARARA_DB") {
            p.db = v.into();
        }
        if let Ok(v) = std::env::var("ARARA_COVERS") {
            p.covers = v.into();
        }
        Self { count: 0, rows: Vec::new(), db_path: p.db, covers_dir: p.covers, resolver: Default::default() }
    }
}

impl TrackModelRust {
    fn cover(&self, hash: &Option<String>, size: u32) -> String {
        hash.as_ref()
            .map(|h| format!("file://{}/{h}-{size}.jpg", self.covers_dir.display()))
            .unwrap_or_default()
    }

    fn track_json(&self, t: &TrackRow) -> serde_json::Value {
        serde_json::json!({
            "id": t.id, "title": t.title, "artist": t.artist, "album": t.album,
            "albumId": t.album_id, "duration": t.duration_ms, "starred": t.starred,
            "url": self.resolver.url(&t.path), "remote": remote::is_remote(&t.path),
            "cover": self.cover(&t.cover_hash, 256), "coverBig": self.cover(&t.cover_hash, 640),
        })
    }
}

impl qobject::TrackModel {
    fn replace_rows(mut self: Pin<&mut Self>, rows: Vec<TrackRow>) {
        let resolver = Db::open(&self.db_path).map(|db| remote::Resolver::load(&db)).unwrap_or_default();
        self.as_mut().begin_reset_model();
        self.as_mut().rust_mut().resolver = resolver;
        let n = rows.len() as i32;
        self.as_mut().rust_mut().rows = rows;
        self.as_mut().end_reset_model();
        self.as_mut().set_count(n);
    }

    pub fn load_all(self: Pin<&mut Self>) {
        let rows = Db::open(&self.db_path).and_then(|db| db.all_tracks()).unwrap_or_default();
        self.replace_rows(rows);
    }

    pub fn search(self: Pin<&mut Self>, query: &QString) {
        let q = query.to_string();
        let rows = Db::open(&self.db_path)
            .and_then(|db| if q.trim().is_empty() { db.all_tracks() } else { db.search(&q, 2000) })
            .unwrap_or_default();
        self.replace_rows(rows);
    }

    pub fn slice_json(&self, from: i32, count: i32) -> QString {
        let from = from.max(0) as usize;
        let end = (from + count.max(0) as usize).min(self.rows.len());
        let v: Vec<_> = self.rows.get(from..end).unwrap_or(&[]).iter().map(|t| self.track_json(t)).collect();
        QString::from(serde_json::to_string(&v).unwrap().as_str())
    }

    pub fn set_starred_at(mut self: Pin<&mut Self>, row: i32, starred: bool) {
        if let Some(r) = self.as_mut().rust_mut().rows.get_mut(row as usize) {
            r.starred = starred;
        }
    }

    pub fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(t) = self.rows.get(index.row() as usize) else { return QVariant::default() };
        let s = |v: &str| QVariant::from(&QString::from(v));
        match ROLES.get((role - 256) as usize).copied() {
            Some("trackId") => QVariant::from(&t.id),
            Some("title") => s(&t.title),
            Some("artist") => s(&t.artist),
            Some("album") => s(t.album.as_deref().unwrap_or("")),
            Some("albumId") => QVariant::from(&t.album_id.unwrap_or(-1)),
            Some("duration") => QVariant::from(&t.duration_ms),
            Some("starred") => QVariant::from(&t.starred),
            Some("cover") => s(&self.cover(&t.cover_hash, 256)),
            Some("coverBig") => s(&self.cover(&t.cover_hash, 640)),
            Some("url") => s(&self.resolver.url(&t.path)),
            Some("remote") => QVariant::from(&remote::is_remote(&t.path)),
            _ => QVariant::default(),
        }
    }

    pub fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut h = QHash::<QHashPair_i32_QByteArray>::default();
        for (i, r) in ROLES.iter().enumerate() {
            h.insert(256 + i as i32, QByteArray::from(*r));
        }
        h
    }

    pub fn row_count(&self, _parent: &QModelIndex) -> i32 {
        self.rows.len() as i32
    }
}
