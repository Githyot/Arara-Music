//! Editing a song's details: title, artists, album, numbers, year, genre,
//! composer and cover.
//!
//! Local files get the new tags written into the file itself (through a temp
//! copy that replaces the original, so a song that is playing keeps playing),
//! which keeps the change when the library is rescanned or opened by another
//! player. When that isn't possible (server songs, read-only or locked disks,
//! or the user said not to touch the file) the change is kept as an override
//! in the database, re-applied every time the scanner or a server sync
//! refreshes that song.

use lofty::config::WriteOptions;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::picture::{MimeType, Picture, PictureType};
use lofty::tag::{Accessor, ItemKey, Tag};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::covers::CoverCache;
use crate::db::{Db, NewTrack};
use crate::Result;

/// The changes for one song. `None` leaves a field as it is; an empty string
/// (or 0 for numbers) clears it. The title can't be cleared.
#[derive(Debug, Default, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackEdit {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artist: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub album_artist: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub album: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub track_no: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub disc_no: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub year: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub genre: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub composer: Option<String>,
    /// New cover, as a hash in the cover cache (set by [`apply`]).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cover_hash: Option<String>,
}

impl TrackEdit {
    pub fn is_empty(&self) -> bool {
        *self == TrackEdit::default()
    }

    /// Later edits win field by field.
    fn merge(&mut self, newer: &TrackEdit) {
        macro_rules! take {
            ($($f:ident),*) => { $( if newer.$f.is_some() { self.$f = newer.$f.clone(); } )* };
        }
        take!(title, artist, album_artist, album, track_no, disc_no, year, genre, composer, cover_hash);
    }

    fn apply_to(&self, d: &mut TrackData) {
        fn text(dst: &mut String, v: &Option<String>) {
            if let Some(v) = v {
                *dst = v.trim().to_owned();
            }
        }
        fn opt_text(dst: &mut Option<String>, v: &Option<String>) {
            if let Some(v) = v {
                let v = v.trim();
                *dst = (!v.is_empty()).then(|| v.to_owned());
            }
        }
        fn num(dst: &mut Option<u32>, v: Option<u32>) {
            if let Some(v) = v {
                *dst = (v > 0).then_some(v);
            }
        }
        if let Some(t) = self.title.as_deref().map(str::trim).filter(|t| !t.is_empty()) {
            d.title = t.to_owned();
        }
        text(&mut d.artist, &self.artist);
        text(&mut d.album_artist, &self.album_artist);
        opt_text(&mut d.album, &self.album);
        num(&mut d.track_no, self.track_no);
        num(&mut d.disc_no, self.disc_no);
        num(&mut d.year, self.year);
        opt_text(&mut d.genre, &self.genre);
        opt_text(&mut d.composer, &self.composer);
        if self.cover_hash.is_some() {
            // The song's own picture now: it also counts when album covers are voted.
            d.cover_hash = self.cover_hash.clone();
            d.art_hash = self.cover_hash.clone();
        }
    }
}

/// An owned copy of [`NewTrack`].
#[derive(Debug, Clone, Default)]
pub(crate) struct TrackData {
    pub path: String,
    pub mtime: i64,
    pub size: i64,
    pub title: String,
    pub artist: String,
    pub album_artist: String,
    pub album: Option<String>,
    pub track_no: Option<u32>,
    pub disc_no: Option<u32>,
    pub year: Option<u32>,
    pub duration_ms: i64,
    pub track_gain: Option<f64>,
    pub album_gain: Option<f64>,
    pub cover_hash: Option<String>,
    pub genre: Option<String>,
    pub composer: Option<String>,
    pub format: Option<String>,
    pub sample_rate: Option<u32>,
    pub bit_depth: Option<u8>,
    pub bitrate: Option<u32>,
    pub explicit: Option<bool>,
    pub art_hash: Option<String>,
    pub folder_art: Option<String>,
}

impl TrackData {
    pub(crate) fn from_new(p: &NewTrack) -> Self {
        let s = |v: Option<&str>| v.map(str::to_owned);
        TrackData {
            path: p.path.to_owned(),
            mtime: p.mtime,
            size: p.size,
            title: p.title.to_owned(),
            artist: p.artist.to_owned(),
            album_artist: p.album_artist.to_owned(),
            album: s(p.album),
            track_no: p.track_no,
            disc_no: p.disc_no,
            year: p.year,
            duration_ms: p.duration_ms,
            track_gain: p.track_gain,
            album_gain: p.album_gain,
            cover_hash: s(p.cover_hash),
            genre: s(p.genre),
            composer: s(p.composer),
            format: s(p.format),
            sample_rate: p.sample_rate,
            bit_depth: p.bit_depth,
            bitrate: p.bitrate,
            explicit: p.explicit,
            art_hash: s(p.art_hash),
            folder_art: s(p.folder_art),
        }
    }

    pub(crate) fn as_new(&self) -> NewTrack<'_> {
        NewTrack {
            path: &self.path,
            mtime: self.mtime,
            size: self.size,
            title: &self.title,
            artist: &self.artist,
            album_artist: &self.album_artist,
            album: self.album.as_deref(),
            track_no: self.track_no,
            disc_no: self.disc_no,
            year: self.year,
            duration_ms: self.duration_ms,
            track_gain: self.track_gain,
            album_gain: self.album_gain,
            cover_hash: self.cover_hash.as_deref(),
            genre: self.genre.as_deref(),
            composer: self.composer.as_deref(),
            format: self.format.as_deref(),
            sample_rate: self.sample_rate,
            bit_depth: self.bit_depth,
            bitrate: self.bitrate,
            explicit: self.explicit,
            art_hash: self.art_hash.as_deref(),
            folder_art: self.folder_art.as_deref(),
        }
    }

    /// The song as the library has it now. `cover_hash` is the picture it
    /// shows (its album's, or its own).
    fn load(c: &Connection, track_id: i64) -> Result<Option<Self>> {
        Ok(c.query_row(
            "SELECT t.path, t.mtime, t.size, t.title, t.artist, COALESCE(ar.name, ''), a.title, t.track_no, t.disc_no,
                    COALESCE(t.year, a.year), t.duration_ms, t.track_gain, t.album_gain, COALESCE(a.cover_hash, t.cover_hash),
                    t.genre, t.composer, t.format, t.sample_rate, t.bit_depth, t.bitrate, t.explicit,
                    t.art_hash, t.folder_art
             FROM tracks t LEFT JOIN albums a ON a.id = t.album_id LEFT JOIN artists ar ON ar.id = a.artist_id
             WHERE t.id = ?1",
            [track_id],
            |r| {
                let artist: String = r.get(4)?;
                let album_artist: String = r.get(5)?;
                Ok(TrackData {
                    path: r.get(0)?,
                    mtime: r.get(1)?,
                    size: r.get(2)?,
                    title: r.get(3)?,
                    album_artist: if album_artist.is_empty() { artist.clone() } else { album_artist },
                    artist,
                    album: r.get(6)?,
                    track_no: r.get(7)?,
                    disc_no: r.get(8)?,
                    year: r.get(9)?,
                    duration_ms: r.get(10)?,
                    track_gain: r.get(11)?,
                    album_gain: r.get(12)?,
                    cover_hash: r.get(13)?,
                    genre: r.get(14)?,
                    composer: r.get(15)?,
                    format: r.get(16)?,
                    sample_rate: r.get(17)?,
                    bit_depth: r.get(18)?,
                    bitrate: r.get(19)?,
                    explicit: r.get::<_, Option<i64>>(20)?.map(|v| v != 0),
                    art_hash: r.get(21)?,
                    folder_art: r.get(22)?,
                })
            },
        )
        .optional()?)
    }
}

/// The saved override for a song, if the user edited it without writing the file.
pub fn override_for(c: &Connection, path: &str) -> Result<Option<TrackEdit>> {
    let json: Option<String> = c
        .prepare_cached("SELECT json FROM track_overrides WHERE path = ?1")?
        .query_row([path], |r| r.get(0))
        .optional()?;
    Ok(json.and_then(|j| serde_json::from_str(&j).ok()))
}

fn save_override(c: &Connection, path: &str, edit: &TrackEdit) -> Result<()> {
    if edit.is_empty() {
        c.execute("DELETE FROM track_overrides WHERE path = ?1", [path])?;
    } else {
        c.execute(
            "INSERT INTO track_overrides(path, json) VALUES (?1, ?2) ON CONFLICT(path) DO UPDATE SET json = excluded.json",
            params![path, serde_json::to_string(edit).unwrap_or_default()],
        )?;
    }
    Ok(())
}

/// Used by `db::upsert_track`: the song with the user's override applied, or
/// None when there's nothing to change.
pub(crate) fn with_override(c: &Connection, p: &NewTrack) -> Result<Option<TrackData>> {
    let Some(edit) = override_for(c, p.path)? else { return Ok(None) };
    let mut d = TrackData::from_new(p);
    edit.apply_to(&mut d);
    Ok(Some(d))
}

/// What the edit dialog shows.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EditableFields {
    pub title: String,
    pub artist: String,
    pub album_artist: String,
    pub album: String,
    pub track_no: u32,
    pub disc_no: u32,
    pub year: u32,
    pub genre: String,
    pub composer: String,
    pub cover_hash: Option<String>,
    pub local: bool,
    /// An override is in effect (changes kept only in the library).
    pub overridden: bool,
}

pub fn fields(db: &Db, track_id: i64) -> Result<Option<EditableFields>> {
    let Some(d) = TrackData::load(&db.conn, track_id)? else { return Ok(None) };
    let overridden = override_for(&db.conn, &d.path)?.is_some();
    Ok(Some(EditableFields {
        local: !d.path.starts_with(crate::remote::PREFIX),
        overridden,
        title: d.title,
        artist: d.artist,
        album_artist: d.album_artist,
        album: d.album.unwrap_or_default(),
        track_no: d.track_no.unwrap_or(0),
        disc_no: d.disc_no.unwrap_or(0),
        year: d.year.unwrap_or(0),
        genre: d.genre.unwrap_or_default(),
        composer: d.composer.unwrap_or_default(),
        cover_hash: d.cover_hash,
    }))
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EditOutcome {
    pub track_id: i64,
    /// The tags were written into the file.
    pub wrote_file: bool,
    /// Why the file couldn't be written (the change is kept in the library).
    pub warning: Option<String>,
}

/// Apply `edit` to one song. `cover` is a new picture (image file bytes).
/// With `write_file`, local files get the tags written into them.
pub fn apply(
    db: &Db,
    covers: &CoverCache,
    track_id: i64,
    mut edit: TrackEdit,
    cover: Option<Vec<u8>>,
    write_file: bool,
) -> Result<EditOutcome> {
    let mut out = EditOutcome { track_id, ..Default::default() };
    let Some(old) = TrackData::load(&db.conn, track_id)? else { return Ok(out) };
    if let Some(bytes) = &cover {
        edit.cover_hash = Some(covers.store(bytes)?);
    }
    let mut new = old.clone();
    edit.apply_to(&mut new);
    // `upsert_track` only sets an album's cover when given one: pass the new
    // picture only, then carry the old one over below if the album changed.
    new.cover_hash = edit.cover_hash.clone();

    let local = !old.path.starts_with(crate::remote::PREFIX);
    if local && write_file {
        match write_tags(Path::new(&old.path), &new, cover.as_deref()) {
            Ok((mtime, size)) => {
                out.wrote_file = true;
                new.mtime = mtime;
                new.size = size;
            }
            Err(e) => out.warning = Some(e),
        }
    }

    let _writer = crate::db::WRITER.lock().unwrap_or_else(|e| e.into_inner());
    let tx = db.conn.unchecked_transaction()?;
    if out.wrote_file {
        // The file now holds everything the dialog showed.
        tx.execute("DELETE FROM track_overrides WHERE path = ?1", [&old.path])?;
    } else {
        let mut saved = override_for(&tx, &old.path)?.unwrap_or_default();
        saved.merge(&edit);
        save_override(&tx, &old.path, &saved)?;
    }
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    crate::db::upsert_track(&tx, &new.as_new(), now)?;
    if edit.cover_hash.is_none() {
        if let Some(h) = &old.cover_hash {
            // Moved to an album without a picture, or out of any album: keep the cover.
            tx.execute(
                "UPDATE albums SET cover_hash = ?1 WHERE cover_hash IS NULL AND id = (SELECT album_id FROM tracks WHERE path = ?2)",
                params![h, old.path],
            )?;
            tx.execute(
                "UPDATE tracks SET cover_hash = ?1 WHERE path = ?2 AND album_id IS NULL AND cover_hash IS NULL",
                params![h, old.path],
            )?;
        }
    }
    if let Some(h) = &edit.cover_hash {
        // A picture chosen by hand is the album's cover: votes never replace it.
        tx.execute(
            "UPDATE albums SET cover_hash = ?1, cover_user = 1 WHERE id = (SELECT album_id FROM tracks WHERE path = ?2)",
            params![h, old.path],
        )?;
    }
    tx.execute("DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL)", [])?;
    // Songs that moved between albums change the votes of both.
    crate::db::pick_album_covers(&tx)?;
    tx.commit()?;
    Ok(out)
}

/// Forget the user's changes that live only in the library. The song is
/// read again from its file (local) on the next scan, or from its server on
/// the next sync. Returns true when there was something to undo.
pub fn revert(db: &Db, track_id: i64) -> Result<bool> {
    let path: Option<String> = db.conn.query_row("SELECT path FROM tracks WHERE id = ?1", [track_id], |r| r.get(0)).optional()?;
    let Some(path) = path else { return Ok(false) };
    let n = db.conn.execute("DELETE FROM track_overrides WHERE path = ?1", [&path])?;
    if n > 0 && !path.starts_with(crate::remote::PREFIX) {
        db.conn.execute("UPDATE tracks SET mtime = 0 WHERE id = ?1", [track_id])?;
    }
    Ok(n > 0)
}

fn mime_of(bytes: &[u8]) -> MimeType {
    match bytes {
        [0x89, b'P', b'N', b'G', ..] => MimeType::Png,
        [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] => MimeType::Unknown("image/webp".into()),
        _ => MimeType::Jpeg,
    }
}

/// Write the song's tags into its file. Works on a copy next to it that then
/// replaces the original in one step: a crash never leaves a half-written
/// file, and a player that has the old file open keeps reading it.
/// Returns the new (mtime, size).
fn write_tags(path: &Path, d: &TrackData, cover: Option<&[u8]>) -> std::result::Result<(i64, i64), String> {
    let explain = |e: &dyn std::fmt::Display| -> String {
        let s = e.to_string();
        if s.contains("ermission denied") || s.contains("Read-only") || s.contains("read-only") {
            "o arquivo ou a pasta não permite gravação".into()
        } else if s.contains("No such file") {
            "o arquivo não foi encontrado (disco desconectado?)".into()
        } else {
            s
        }
    };
    let stem = path.file_stem().ok_or("caminho inválido")?.to_string_lossy().into_owned();
    let ext = path.extension().map(|e| e.to_string_lossy().into_owned()).unwrap_or_default();
    // Hidden (the scanner skips dot files), same extension (lofty detects the format by it).
    let tmp = path.with_file_name(format!(".{stem}.arara-edit.{ext}"));
    std::fs::copy(path, &tmp).map_err(|e| explain(&e))?;
    let result = (|| -> std::result::Result<(), String> {
        let mut tagged = lofty::read_from_path(&tmp).map_err(|e| explain(&e))?;
        if tagged.primary_tag().is_none() {
            let tt = tagged.primary_tag_type();
            tagged.insert_tag(Tag::new(tt));
        }
        let tag = tagged.primary_tag_mut().ok_or("formato sem suporte a etiquetas")?;
        tag.set_title(d.title.clone());
        fn set(tag: &mut Tag, key: ItemKey, v: &str) {
            if v.is_empty() {
                tag.remove_key(&key);
            } else {
                tag.insert_text(key, v.to_owned());
            }
        }
        set(tag, ItemKey::TrackArtist, &d.artist);
        // Only store an album artist that differs: most files don't have one.
        let had_aa = tag.get_string(&ItemKey::AlbumArtist).is_some();
        if had_aa || d.album_artist != d.artist {
            set(tag, ItemKey::AlbumArtist, &d.album_artist);
        }
        set(tag, ItemKey::AlbumTitle, d.album.as_deref().unwrap_or(""));
        set(tag, ItemKey::Genre, d.genre.as_deref().unwrap_or(""));
        set(tag, ItemKey::Composer, d.composer.as_deref().unwrap_or(""));
        match d.track_no {
            Some(n) => tag.set_track(n),
            None => tag.remove_track(),
        }
        match d.disc_no {
            Some(n) => tag.set_disk(n),
            None => tag.remove_disk(),
        }
        match d.year {
            Some(y) => tag.set_year(y),
            None => tag.remove_year(),
        }
        if let Some(bytes) = cover {
            tag.remove_picture_type(PictureType::CoverFront);
            tag.remove_picture_type(PictureType::Other);
            tag.push_picture(Picture::new_unchecked(PictureType::CoverFront, Some(mime_of(bytes)), None, bytes.to_vec()));
        }
        tagged.save_to_path(&tmp, WriteOptions::default()).map_err(|e| explain(&e))?;
        Ok(())
    })();
    if let Err(e) = result {
        let _ = std::fs::remove_file(&tmp);
        return Err(e);
    }
    if let Err(e) = std::fs::rename(&tmp, path) {
        let _ = std::fs::remove_file(&tmp);
        return Err(explain(&e));
    }
    let md = std::fs::metadata(path).map_err(|e| explain(&e))?;
    let mtime = md
        .modified()
        .ok()
        .and_then(|m| m.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    Ok((mtime, md.len() as i64))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scanner;

    fn wav(path: &Path) {
        let samples = 8000u32;
        let mut b = Vec::new();
        b.extend_from_slice(b"RIFF");
        b.extend_from_slice(&(36 + samples * 2).to_le_bytes());
        b.extend_from_slice(b"WAVEfmt ");
        b.extend_from_slice(&16u32.to_le_bytes());
        b.extend_from_slice(&1u16.to_le_bytes());
        b.extend_from_slice(&1u16.to_le_bytes());
        b.extend_from_slice(&8000u32.to_le_bytes());
        b.extend_from_slice(&16000u32.to_le_bytes());
        b.extend_from_slice(&2u16.to_le_bytes());
        b.extend_from_slice(&16u16.to_le_bytes());
        b.extend_from_slice(b"data");
        b.extend_from_slice(&(samples * 2).to_le_bytes());
        b.resize(b.len() + samples as usize * 2, 0);
        std::fs::write(path, b).unwrap();
    }

    fn setup() -> (tempfile::TempDir, Db, CoverCache, Vec<std::path::PathBuf>) {
        let tmp = tempfile::tempdir().unwrap();
        let music = tmp.path().join("music");
        std::fs::create_dir_all(music.join("Disco")).unwrap();
        wav(&music.join("Disco/faixa.wav"));
        wav(&music.join("Disco/outra.wav"));
        let mut db = Db::open(&tmp.path().join("db.sqlite")).unwrap();
        let covers = CoverCache::new(tmp.path().join("covers")).unwrap();
        let roots = vec![music];
        scanner::scan(&mut db, &covers, &roots, |_| {}).unwrap();
        (tmp, db, covers, roots)
    }

    fn id_of(db: &Db, file: &str) -> i64 {
        db.conn.query_row("SELECT id FROM tracks WHERE path LIKE ?1", [format!("%{file}")], |r| r.get(0)).unwrap()
    }

    fn edit() -> TrackEdit {
        TrackEdit {
            title: Some("Voo da Arara".into()),
            artist: Some("Banda Azul".into()),
            album: Some("Céu Aberto".into()),
            track_no: Some(3),
            year: Some(2021),
            genre: Some("Rock".into()),
            ..Default::default()
        }
    }

    #[test]
    fn writes_file_and_survives_rescan() {
        let (_tmp, mut db, covers, roots) = setup();
        let id = id_of(&db, "faixa.wav");
        let out = apply(&db, &covers, id, edit(), None, true).unwrap();
        assert!(out.wrote_file, "{:?}", out.warning);
        let t = db.track(id).unwrap().unwrap();
        assert_eq!((t.title.as_str(), t.artist.as_str(), t.album.as_deref()), ("Voo da Arara", "Banda Azul", Some("Céu Aberto")));
        assert_eq!(t.year, Some(2021));
        assert!(override_for(&db.conn, &t.path).unwrap().is_none());

        // The file itself has the tags: a full re-read keeps them.
        db.conn.execute("UPDATE tracks SET mtime = 0", []).unwrap();
        scanner::scan(&mut db, &covers, &roots, |_| {}).unwrap();
        let t = db.track(id).unwrap().unwrap();
        assert_eq!(t.title, "Voo da Arara");
        assert_eq!(t.genre.as_deref(), Some("Rock"));
        assert_eq!(db.search("arara", 10).unwrap().len(), 1);
        // No temp file left behind.
        let leftovers = std::fs::read_dir(roots[0].join("Disco")).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with('.')).count();
        assert_eq!(leftovers, 0);
    }

    #[test]
    fn library_only_edit_is_kept_and_can_be_undone() {
        let (_tmp, mut db, covers, roots) = setup();
        let id = id_of(&db, "outra.wav");
        let out = apply(&db, &covers, id, edit(), None, false).unwrap();
        assert!(!out.wrote_file);
        let f = fields(&db, id).unwrap().unwrap();
        assert!(f.overridden);
        assert_eq!(f.title, "Voo da Arara");
        assert_eq!(f.track_no, 3);

        // A rescan reading the (unchanged) file keeps the user's version.
        db.conn.execute("UPDATE tracks SET mtime = 0", []).unwrap();
        scanner::scan(&mut db, &covers, &roots, |_| {}).unwrap();
        assert_eq!(db.track(id).unwrap().unwrap().title, "Voo da Arara");

        // A second edit only changes what it sends.
        apply(&db, &covers, id, TrackEdit { genre: Some("".into()), ..Default::default() }, None, false).unwrap();
        let t = db.track(id).unwrap().unwrap();
        assert_eq!((t.title.as_str(), t.genre.as_deref()), ("Voo da Arara", None));

        assert!(revert(&db, id).unwrap());
        scanner::scan(&mut db, &covers, &roots, |_| {}).unwrap();
        assert_eq!(db.track(id).unwrap().unwrap().title, "outra");
    }

    #[test]
    fn renaming_the_album_moves_the_cover_and_drops_the_empty_album() {
        let (_tmp, db, covers, _roots) = setup();
        let a = id_of(&db, "faixa.wav");
        let b = id_of(&db, "outra.wav");
        // Put both in one album with a cover.
        let png = {
            let img = image::RgbImage::from_pixel(4, 4, image::Rgb([200, 30, 30]));
            let mut v = std::io::Cursor::new(Vec::new());
            img.write_to(&mut v, image::ImageFormat::Png).unwrap();
            v.into_inner()
        };
        let one = TrackEdit { album: Some("Primeiro".into()), artist: Some("X".into()), album_artist: Some("X".into()), ..Default::default() };
        apply(&db, &covers, a, one.clone(), Some(png), false).unwrap();
        apply(&db, &covers, b, one, None, false).unwrap();
        let ta = db.track(a).unwrap().unwrap();
        let tb = db.track(b).unwrap().unwrap();
        assert_eq!(ta.album_id, tb.album_id);
        assert!(tb.cover_hash.is_some(), "album cover is shared");

        // Rename the album of both: the new album keeps the picture, the old one goes.
        let two = TrackEdit { album: Some("Segundo".into()), ..Default::default() };
        apply(&db, &covers, a, two.clone(), None, false).unwrap();
        apply(&db, &covers, b, two, None, false).unwrap();
        let ta = db.track(a).unwrap().unwrap();
        assert_eq!(ta.album.as_deref(), Some("Segundo"));
        assert_eq!(ta.cover_hash, tb.cover_hash);
        let titles: Vec<String> = db.albums().unwrap().into_iter().map(|a| a.title).collect();
        assert_eq!(titles, vec!["Segundo".to_string()]);
    }
}
