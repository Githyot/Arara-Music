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
        include!("cxx-qt-lib/qlist.h");
        type QList_i32 = cxx_qt_lib::QList<i32>;
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

        /// Search with filters (artista:, genero:, ano:, pasta:…) and a sort order
        /// ("artist", "title", "album", "added", "year", "plays", "duration").
        #[qinvokable]
        fn query(self: Pin<&mut TrackModel>, query: &QString, sort: &QString);

        /// JSON [{l: "A", row: 0}, …]: first row of each index letter (or year).
        #[qinvokable]
        fn sections(self: &TrackModel) -> QString;

        /// Index letter (or year) of one row, for the scroll bubble.
        #[qinvokable]
        #[cxx_name = "sectionAt"]
        fn section_at(self: &TrackModel, row: i32) -> QString;

        /// JSON array of track objects for rows [from, from+count) — used to build a play queue.
        #[qinvokable]
        #[cxx_name = "sliceJson"]
        fn slice_json(self: &TrackModel, from: i32, count: i32) -> QString;

        /// JSON array of up to `count` tracks picked at random from every row
        /// (not just the first ones), already shuffled — for "Aleatório".
        #[qinvokable]
        #[cxx_name = "shuffledJson"]
        fn shuffled_json(self: &TrackModel, count: i32) -> QString;

        #[qinvokable]
        #[cxx_name = "setStarredAt"]
        fn set_starred_at(self: Pin<&mut TrackModel>, row: i32, starred: bool);

        /// Update a row's explicit state in place (after the user changes it).
        #[qinvokable]
        #[cxx_name = "setExplicitAt"]
        fn set_explicit_at(self: Pin<&mut TrackModel>, row: i32, kind: i32);

        #[inherit]
        #[cxx_name = "dataChanged"]
        fn data_changed(self: Pin<&mut TrackModel>, top_left: &QModelIndex, bottom_right: &QModelIndex, roles: &QList_i32);

        #[inherit]
        fn index(self: &TrackModel, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex;

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
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QList, QModelIndex, QString, QVariant};
use std::path::PathBuf;

const ROLES: &[&str] = &["trackId", "title", "artist", "album", "albumId", "duration", "starred", "cover", "coverBig", "url", "remote", "quality", "explicit"];

pub struct TrackModelRust {
    count: i32,
    rows: Vec<TrackRow>,
    db_path: PathBuf,
    covers_dir: PathBuf,
    resolver: remote::Resolver,
    sort: String,
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
        Self { count: 0, rows: Vec::new(), db_path: p.db, covers_dir: p.covers, resolver: Default::default(), sort: String::new() }
    }
}

impl TrackModelRust {
    fn cover(&self, hash: &Option<String>, size: u32) -> String {
        hash.as_ref()
            .map(|h| remote::file_url(&self.covers_dir.join(format!("{h}-{size}.jpg")).to_string_lossy()))
            .unwrap_or_default()
    }

    fn track_json(&self, t: &TrackRow) -> serde_json::Value {
        serde_json::json!({
            "id": t.id, "title": t.title, "artist": t.artist, "album": t.album,
            "albumId": t.album_id, "duration": t.duration_ms, "starred": t.starred,
            "url": self.resolver.url(&t.path), "remote": remote::is_remote(&t.path),
            "gain": t.track_gain, "albumGain": t.album_gain, "year": t.year, "genre": t.genre,
            "quality": t.quality().0, "qualityDetail": t.quality().1, "explicit": t.explicit,
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

    pub fn search(mut self: Pin<&mut Self>, query: &QString) {
        self.as_mut().rust_mut().sort = String::new();
        let q = query.to_string();
        let rows = Db::open(&self.db_path)
            .and_then(|db| if q.trim().is_empty() { db.all_tracks() } else { db.search(&q, 2000) })
            .unwrap_or_default();
        self.replace_rows(rows);
    }

    pub fn query(mut self: Pin<&mut Self>, query: &QString, sort: &QString) {
        let (q, sort) = (query.to_string(), sort.to_string());
        let rows = Db::open(&self.db_path)
            .and_then(|db| db.query_tracks(&q, &sort, 0))
            .unwrap_or_default();
        // A relevance-ranked search has no index letters.
        let has_text = !arara_core::query::parse(&q).text.is_empty();
        self.as_mut().rust_mut().sort = if has_text && sort.is_empty() { "rank".into() } else { sort };
        self.replace_rows(rows);
    }

    pub fn sections(&self) -> QString {
        let mut out = Vec::new();
        let mut last = String::new();
        for (i, t) in self.rows.iter().enumerate() {
            let l = arara_core::query::section_of(t, &self.sort);
            if l.is_empty() {
                break;
            }
            if l != last {
                out.push(serde_json::json!({ "l": l, "row": i }));
                last = l;
            }
        }
        QString::from(serde_json::to_string(&out).unwrap().as_str())
    }

    pub fn section_at(&self, row: i32) -> QString {
        let l = self.rows.get(row.max(0) as usize).map(|t| arara_core::query::section_of(t, &self.sort)).unwrap_or_default();
        QString::from(l.as_str())
    }

    pub fn slice_json(&self, from: i32, count: i32) -> QString {
        let from = from.max(0) as usize;
        let end = (from + count.max(0) as usize).min(self.rows.len());
        let v: Vec<_> = self.rows.get(from..end).unwrap_or(&[]).iter().map(|t| self.track_json(t)).collect();
        QString::from(serde_json::to_string(&v).unwrap().as_str())
    }

    pub fn shuffled_json(&self, count: i32) -> QString {
        let n = self.rows.len();
        let take = (count.max(0) as usize).min(n);
        // Partial Fisher–Yates over row indices with a time-seeded xorshift:
        // a fair sample of the whole result, without a rand dependency.
        let mut seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0x9e37_79b9_7f4a_7c15)
            | 1;
        let mut next = move || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        let mut idx: Vec<usize> = (0..n).collect();
        for i in 0..take {
            let j = i + (next() % (n - i) as u64) as usize;
            idx.swap(i, j);
        }
        let v: Vec<_> = idx[..take].iter().map(|&i| self.track_json(&self.rows[i])).collect();
        QString::from(serde_json::to_string(&v).unwrap().as_str())
    }

    pub fn set_starred_at(mut self: Pin<&mut Self>, row: i32, starred: bool) {
        if let Some(r) = self.as_mut().rust_mut().rows.get_mut(row as usize) {
            r.starred = starred;
        }
    }

    pub fn set_explicit_at(mut self: Pin<&mut Self>, row: i32, kind: i32) {
        {
            let mut rust = self.as_mut().rust_mut();
            let Some(r) = rust.rows.get_mut(row as usize) else { return };
            r.explicit = kind as i64;
        }
        let idx = self.index(row, 0, &QModelIndex::default());
        let role = 256 + ROLES.iter().position(|r| *r == "explicit").unwrap() as i32;
        let mut roles = QList::<i32>::default();
        roles.append(role);
        self.as_mut().data_changed(&idx, &idx, &roles);
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
            Some("quality") => s(t.quality().0),
            Some("explicit") => QVariant::from(&(t.explicit as i32)),
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
