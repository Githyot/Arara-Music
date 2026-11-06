//! Import playlists and likes exported from streaming services, and match
//! them against the library (local files and synced servers).
//!
//! Nothing is streamed from those services: their audio is DRM-protected
//! (Apple Music) or only reachable by breaking the terms of use (YouTube
//! Music). What we can do cleanly is bring the *collection* over: playlists
//! become Arara playlists with the songs you already have, likes become
//! favourites, and the rest is listed as missing.
//!
//! Accepted inputs (a file, or a folder searched recursively):
//! - Apple Music / iTunes "Library.xml" (Music app: Arquivo › Biblioteca › Exportar Biblioteca)
//! - Apple privacy export JSON ("Apple Music Library Tracks.json" and similar)
//! - Google Takeout "YouTube e YouTube Music" CSVs (library songs, playlists)
//! - Generic CSV from Exportify, TuneMyMusic, Soundiiz… (title/artist/album columns)
//! - M3U/M3U8 and XSPF playlists

use crate::db::{Db, TrackRow};
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use unicode_normalization::UnicodeNormalization;

pub type R<T> = std::result::Result<T, String>;

#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Entry {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration_ms: Option<i64>,
}

#[derive(Clone, Debug, Default)]
pub struct Playlist {
    pub name: String,
    /// "Apple Music", "YouTube Music" or "importada"
    pub source: String,
    /// Likes / loved songs: matched tracks are starred instead of becoming a playlist.
    pub liked: bool,
    pub entries: Vec<Entry>,
    /// Rows we could not use (e.g. Takeout CSVs that only carry a video id).
    pub unreadable: usize,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Missing {
    pub playlist: String,
    #[serde(flatten)]
    pub entry: Entry,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Report {
    pub playlists: usize,
    pub total: usize,
    pub matched: usize,
    pub starred: usize,
    pub unreadable: usize,
    pub missing: Vec<Missing>,
}

// ---------- normalization & matching ----------

/// Lowercase, no accents, no "(feat. …)", "[Official Video]", "- Remastered 2011", punctuation collapsed.
pub fn norm(s: &str) -> String {
    let mut t: String = s.nfd().filter(|c| !unicode_normalization::char::is_combining_mark(*c)).collect::<String>().to_lowercase();
    // drop bracketed decorations
    for (open, close) in [('(', ')'), ('[', ']')] {
        while let (Some(a), Some(b)) = (t.find(open), t.find(close)) {
            if b <= a {
                break;
            }
            t.replace_range(a..=b, " ");
        }
    }
    for cut in [" - remaster", " - live", " - ao vivo", " - single version", " - radio edit", " feat. ", " ft. ", " featuring "] {
        if let Some(i) = t.find(cut) {
            t.truncate(i);
        }
    }
    let t = t.replace('&', " e ").replace(" and ", " e ");
    t.split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()).collect::<Vec<_>>().join(" ")
}

fn artist_matches(lib: &str, wanted: &str) -> bool {
    if wanted.is_empty() {
        return true;
    }
    let (a, b) = (norm(lib), norm(wanted));
    if a.is_empty() {
        return false;
    }
    if a == b || a.contains(&b) || b.contains(&a) {
        return true;
    }
    // "A, B & C" vs "A": any credited artist in common
    let parts = |s: &str| -> Vec<String> {
        s.split([',', '&', '/', ';']).flat_map(|p| p.split(" e ")).map(norm).filter(|p| !p.is_empty()).collect()
    };
    let pa = parts(lib);
    parts(wanted).iter().any(|w| pa.contains(w))
}

pub struct Matcher {
    tracks: Vec<TrackRow>,
    by_title: HashMap<String, Vec<usize>>,
}

impl Matcher {
    pub fn new(tracks: Vec<TrackRow>) -> Self {
        let mut by_title: HashMap<String, Vec<usize>> = HashMap::new();
        for (i, t) in tracks.iter().enumerate() {
            by_title.entry(norm(&t.title)).or_default().push(i);
        }
        Self { tracks, by_title }
    }

    pub fn find(&self, e: &Entry) -> Option<&TrackRow> {
        let cands = self.by_title.get(&norm(&e.title))?;
        cands
            .iter()
            .map(|&i| &self.tracks[i])
            .filter(|t| artist_matches(&t.artist, &e.artist))
            .filter(|t| match e.duration_ms {
                // a different edit of the song is still better than nothing, but not a 2× longer live take
                Some(d) if d > 0 && t.duration_ms > 0 => (t.duration_ms - d).abs() < 30_000,
                _ => true,
            })
            .min_by_key(|t| {
                let album_bonus = if !e.album.is_empty() && t.album.as_deref().map(norm) == Some(norm(&e.album)) { 0 } else { 1 };
                let dd = e.duration_ms.map(|d| (t.duration_ms - d).abs()).unwrap_or(0);
                (album_bonus, dd)
            })
    }
}

// ---------- readers ----------

fn source_from_path(p: &Path) -> String {
    let s = p.to_string_lossy().to_lowercase();
    if s.contains("youtube") {
        "YouTube Music".into()
    } else if s.contains("apple") || s.contains("itunes") {
        "Apple Music".into()
    } else {
        "importada".into()
    }
}

fn is_likes_name(name: &str) -> bool {
    let n = norm(name);
    ["liked", "curtid", "favorit", "loved", "gostei", "likes"].iter().any(|k| n.contains(k))
}

/// "Artist - Title (Official Video)" → (artist, title)
fn split_artist_title(s: &str) -> (String, String) {
    for sep in [" - ", " – ", " — "] {
        if let Some((a, t)) = s.split_once(sep) {
            return (a.trim().to_string(), t.trim().to_string());
        }
    }
    (String::new(), s.trim().to_string())
}

fn clean_channel(s: &str) -> String {
    s.trim().trim_end_matches(" - Topic").trim_end_matches("VEVO").trim().to_string()
}

fn header_index(headers: &[String], names: &[&str]) -> Option<usize> {
    let h: Vec<String> = headers.iter().map(|x| norm(x)).collect();
    names.iter().find_map(|n| h.iter().position(|x| x == n))
}

fn parse_duration(s: &str) -> Option<i64> {
    let s = s.trim();
    if s.is_empty() {
        return None;
    }
    if s.contains(':') {
        let mut total = 0i64;
        for part in s.split(':') {
            total = total * 60 + part.trim().parse::<f64>().ok()? as i64;
        }
        return Some(total * 1000);
    }
    let v: f64 = s.parse().ok()?;
    // seconds or milliseconds
    Some(if v > 10_000.0 { v as i64 } else { (v * 1000.0) as i64 })
}

fn read_csv(path: &Path) -> R<Option<Playlist>> {
    let mut rdr = csv::ReaderBuilder::new().flexible(true).from_path(path).map_err(|e| e.to_string())?;
    let headers: Vec<String> = rdr.headers().map_err(|e| e.to_string())?.iter().map(str::to_owned).collect();
    let ti = header_index(&headers, &["song title", "track name", "title", "titulo", "name", "nome", "song", "musica", "track"]);
    let ai = header_index(&headers, &["artist name 1", "artist name s", "artist names", "artist name", "artist", "artista", "artists", "channel", "creator"]);
    let li = header_index(&headers, &["album title", "album name", "album", "release"]);
    let di = header_index(&headers, &["duration ms", "track duration ms", "duration", "duracao", "length", "time"]);
    let vid = header_index(&headers, &["video id", "video id s", "id do video"]);
    let mut pl = Playlist {
        name: path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default(),
        source: source_from_path(path),
        ..Default::default()
    };
    pl.liked = is_likes_name(&pl.name);
    if ti.is_none() && vid.is_none() {
        return Ok(None); // not a track list
    }
    for rec in rdr.records().flatten() {
        let get = |i: Option<usize>| i.and_then(|i| rec.get(i)).unwrap_or("").trim().to_string();
        let title = get(ti);
        if title.is_empty() {
            if !get(vid).is_empty() {
                pl.unreadable += 1;
            }
            continue;
        }
        let mut artist = clean_channel(&get(ai));
        let mut title = title;
        if artist.is_empty() {
            let (a, t) = split_artist_title(&title);
            artist = a;
            title = t;
        }
        pl.entries.push(Entry { title, artist, album: get(li), duration_ms: di.and_then(|i| rec.get(i)).and_then(parse_duration) });
    }
    Ok(Some(pl))
}

fn json_str(v: &Value, keys: &[&str]) -> String {
    keys.iter().find_map(|k| v.get(*k).and_then(|x| x.as_str())).unwrap_or("").trim().to_string()
}

fn read_json(path: &Path) -> R<Option<Playlist>> {
    let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let v: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let items = match &v {
        Value::Array(a) => a.clone(),
        Value::Object(o) => o.values().find_map(|x| x.as_array().cloned()).unwrap_or_default(),
        _ => return Ok(None),
    };
    let mut pl = Playlist {
        name: path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default(),
        source: source_from_path(path),
        ..Default::default()
    };
    pl.liked = is_likes_name(&pl.name);
    for it in &items {
        let title = json_str(it, &["Title", "Song Name", "Track Name", "title", "name", "Name", "Content Name"]);
        if title.is_empty() {
            continue;
        }
        let artist = json_str(it, &["Artist", "Artist Name", "artist", "artistName", "Container Artist Name"]);
        let album = json_str(it, &["Album", "Album Name", "album", "albumName", "Container Album Name"]);
        let duration_ms = ["Track Duration", "Duration", "duration", "durationInMillis", "Media Duration In Milliseconds"]
            .iter()
            .find_map(|k| it.get(*k))
            .and_then(|d| d.as_i64().or_else(|| d.as_str().and_then(parse_duration)));
        pl.entries.push(Entry { title, artist, album, duration_ms });
    }
    Ok((!pl.entries.is_empty()).then_some(pl))
}

/// Apple Music / iTunes Library.xml: every user playlist plus the loved/favourited songs.
fn read_itunes_xml(path: &Path) -> R<Vec<Playlist>> {
    let v = plist::Value::from_file(path).map_err(|e| e.to_string())?;
    let root = v.as_dictionary().ok_or("plist inválido")?;
    let Some(tracks) = root.get("Tracks").and_then(|t| t.as_dictionary()) else { return Ok(vec![]) };
    let s = |d: &plist::Dictionary, k: &str| d.get(k).and_then(|x| x.as_string()).unwrap_or("").to_string();
    let mut by_id: HashMap<String, (Entry, bool)> = HashMap::new();
    for (id, t) in tracks {
        let Some(d) = t.as_dictionary() else { continue };
        let loved = ["Loved", "Favorited"].iter().any(|k| d.get(*k).and_then(|x| x.as_boolean()).unwrap_or(false));
        let e = Entry {
            title: s(d, "Name"),
            artist: s(d, "Artist"),
            album: s(d, "Album"),
            duration_ms: d.get("Total Time").and_then(|x| x.as_signed_integer()),
        };
        by_id.insert(id.clone(), (e, loved));
    }
    let mut out = Vec::new();
    let liked: Vec<Entry> = by_id.values().filter(|(_, l)| *l).map(|(e, _)| e.clone()).collect();
    if !liked.is_empty() {
        out.push(Playlist { name: "Amadas".into(), source: "Apple Music".into(), liked: true, entries: liked, unreadable: 0 });
    }
    for p in root.get("Playlists").and_then(|p| p.as_array()).into_iter().flatten() {
        let Some(d) = p.as_dictionary() else { continue };
        // skip the whole-library and smart system playlists (Music, Movies, Downloaded…)
        if d.get("Master").is_some() || d.get("Distinguished Kind").is_some() || d.get("Folder").and_then(|x| x.as_boolean()) == Some(true) {
            continue;
        }
        let entries: Vec<Entry> = d
            .get("Playlist Items")
            .and_then(|x| x.as_array())
            .into_iter()
            .flatten()
            .filter_map(|it| it.as_dictionary()?.get("Track ID")?.as_signed_integer())
            .filter_map(|id| by_id.get(&id.to_string()).map(|(e, _)| e.clone()))
            .collect();
        if !entries.is_empty() {
            let name = s(d, "Name");
            out.push(Playlist { liked: is_likes_name(&name), name, source: "Apple Music".into(), entries, unreadable: 0 });
        }
    }
    Ok(out)
}

fn read_m3u(path: &Path) -> R<Option<Playlist>> {
    let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut pl = Playlist {
        name: path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default(),
        source: source_from_path(path),
        ..Default::default()
    };
    let mut pending: Option<(Option<i64>, String)> = None;
    for line in text.lines().map(str::trim).filter(|l| !l.is_empty()) {
        if let Some(info) = line.strip_prefix("#EXTINF:") {
            let (dur, label) = info.split_once(',').unwrap_or(("", info));
            let d = dur.trim().parse::<i64>().ok().filter(|d| *d > 0).map(|d| d * 1000);
            pending = Some((d, label.to_string()));
        } else if line.starts_with("#PLAYLIST:") {
            pl.name = line[10..].trim().to_string();
        } else if !line.starts_with('#') {
            let (d, label) = pending.take().unwrap_or_else(|| {
                let stem = Path::new(line).file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
                (None, stem)
            });
            let (artist, title) = split_artist_title(&label);
            pl.entries.push(Entry { title, artist, album: String::new(), duration_ms: d });
        }
    }
    pl.liked = is_likes_name(&pl.name);
    Ok((!pl.entries.is_empty()).then_some(pl))
}

fn xml_tag(block: &str, tag: &str) -> String {
    let (o, c) = (format!("<{tag}>"), format!("</{tag}>"));
    block
        .find(&o)
        .and_then(|a| block[a + o.len()..].find(&c).map(|b| &block[a + o.len()..a + o.len() + b]))
        .map(|s| s.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'"))
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn read_xspf(path: &Path) -> R<Option<Playlist>> {
    let text = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let head = text.split("<trackList>").next().unwrap_or("");
    let mut name = xml_tag(head, "title");
    if name.is_empty() {
        name = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    }
    let mut pl = Playlist { liked: is_likes_name(&name), name, source: source_from_path(path), ..Default::default() };
    for block in text.split("<track>").skip(1) {
        let title = xml_tag(block, "title");
        if title.is_empty() {
            continue;
        }
        pl.entries.push(Entry {
            title,
            artist: xml_tag(block, "creator"),
            album: xml_tag(block, "album"),
            duration_ms: xml_tag(block, "duration").parse().ok(),
        });
    }
    Ok((!pl.entries.is_empty()).then_some(pl))
}

fn read_file(path: &Path) -> R<Vec<Playlist>> {
    let ext = path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
    Ok(match ext.as_str() {
        "csv" => read_csv(path)?.into_iter().collect(),
        "json" => read_json(path)?.into_iter().collect(),
        "xml" | "plist" => read_itunes_xml(path)?,
        "m3u" | "m3u8" => read_m3u(path)?.into_iter().collect(),
        "xspf" => read_xspf(path)?.into_iter().collect(),
        _ => vec![],
    })
}

/// Reads one export file, or every supported file under a folder (e.g. an unzipped Takeout).
pub fn read_path(path: &Path) -> R<Vec<Playlist>> {
    if path.is_file() {
        return read_file(path);
    }
    if !path.is_dir() {
        return Err("arquivo ou pasta não encontrado".into());
    }
    let mut files: Vec<PathBuf> = walkdir::WalkDir::new(path)
        .into_iter()
        .flatten()
        .filter(|e| e.file_type().is_file())
        .map(|e| e.into_path())
        .collect();
    files.sort();
    let mut out = Vec::new();
    for f in files {
        // one unreadable file shouldn't stop the rest
        if let Ok(mut p) = read_file(&f) {
            out.append(&mut p);
        }
    }
    Ok(out)
}

/// Creates/replaces the playlists, stars liked songs, and reports what's missing.
pub fn apply(db: &Db, playlists: &[Playlist]) -> crate::Result<Report> {
    let matcher = Matcher::new(db.all_tracks()?);
    let mut rep = Report::default();
    let existing: HashMap<String, i64> = db.playlists()?.into_iter().map(|p| (p.name, p.id)).collect();
    for pl in playlists {
        rep.total += pl.entries.len();
        rep.unreadable += pl.unreadable;
        let mut ids = Vec::new();
        for e in &pl.entries {
            match matcher.find(e) {
                Some(t) => {
                    rep.matched += 1;
                    if !ids.contains(&t.id) {
                        ids.push(t.id);
                    }
                }
                None => rep.missing.push(Missing { playlist: pl.name.clone(), entry: e.clone() }),
            }
        }
        if pl.liked {
            for id in &ids {
                db.set_starred(*id, true)?;
            }
            rep.starred += ids.len();
        } else if !ids.is_empty() {
            let name = if pl.source == "importada" { pl.name.clone() } else { format!("{} ({})", pl.name, pl.source) };
            // re-importing replaces the old copy instead of duplicating it
            if let Some(old) = existing.get(&name) {
                db.delete_playlist(*old)?;
            }
            let id = db.create_playlist(&name)?;
            db.add_to_playlist(id, &ids)?;
            rep.playlists += 1;
        }
    }
    Ok(rep)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_titles() {
        assert_eq!(norm("Águas de Março (Remastered 2011)"), "aguas de marco");
        assert_eq!(norm("Song [Official Video]"), "song");
        assert_eq!(norm("Help! - Remastered 2009"), "help");
        assert_eq!(norm("Under Pressure feat. David Bowie"), "under pressure");
        assert!(artist_matches("Elis Regina & Tom Jobim", "Tom Jobim"));
        assert!(!artist_matches("Elis Regina", "Gal Costa"));
    }

    fn db_with(rows: &[(&str, &str, &str, i64)]) -> Db {
        let db = Db::open_in_memory().unwrap();
        for (i, (t, a, al, d)) in rows.iter().enumerate() {
            crate::db::upsert_track(
                &db.conn,
                &crate::db::NewTrack {
                    path: &format!("/m/{i}.mp3"),
                    mtime: 0,
                    size: 0,
                    title: t,
                    artist: a,
                    album_artist: a,
                    album: Some(al),
                    track_no: None,
                    disc_no: None,
                    year: None,
                    duration_ms: *d,
                    track_gain: None,
                    album_gain: None,
                    cover_hash: None,
                    genre: None,
                    composer: None,
                    format: None, sample_rate: None, bit_depth: None, bitrate: None, explicit: None,
                },
                0,
            )
            .unwrap();
        }
        db
    }

    #[test]
    fn imports_csv_and_m3u_and_matches() {
        let db = db_with(&[
            ("Águas de Março", "Elis Regina & Tom Jobim", "Elis & Tom", 213_000),
            ("Garota de Ipanema", "Tom Jobim", "The Composer", 190_000),
            ("Garota de Ipanema", "Tom Jobim", "Ao Vivo", 420_000),
        ]);
        let dir = tempfile::tempdir().unwrap();
        let yt = dir.path().join("YouTube e YouTube Music/playlists");
        std::fs::create_dir_all(&yt).unwrap();
        std::fs::write(
            yt.join("Bossa.csv"),
            "Song Title,Album Title,Artist Name 1,Duration\n\"Aguas de Marco (Remastered)\",Elis & Tom,Tom Jobim - Topic,3:33\nNão Tenho,X,Ninguém,1:00\n",
        )
        .unwrap();
        std::fs::write(yt.join("Liked music.csv"), "Video ID,Title\nabc,Tom Jobim - Garota de Ipanema (Official Audio)\nxyz,\n").unwrap();
        std::fs::write(dir.path().join("mix.m3u"), "#EXTM3U\n#EXTINF:191,Tom Jobim - Garota de Ipanema\nhttp://x\n").unwrap();

        let pls = read_path(dir.path()).unwrap();
        assert_eq!(pls.len(), 3);
        let rep = apply(&db, &pls).unwrap();
        assert_eq!(rep.total, 4);
        assert_eq!(rep.matched, 3);
        assert_eq!(rep.starred, 1);
        assert_eq!(rep.unreadable, 1);
        assert_eq!(rep.missing.len(), 1);
        assert_eq!(rep.missing[0].entry.title, "Não Tenho");
        let names: Vec<String> = db.playlists().unwrap().into_iter().map(|p| p.name).collect();
        assert!(names.contains(&"Bossa (YouTube Music)".to_string()), "{names:?}");
        // the studio take (190 s) is picked over the 7-minute live one
        let mix = db.playlists().unwrap().into_iter().find(|p| p.name == "mix").unwrap();
        let t = db.playlist_tracks(mix.id).unwrap();
        assert_eq!(t[0].duration_ms, 190_000);
        // re-import doesn't duplicate
        apply(&db, &pls).unwrap();
        assert_eq!(db.playlists().unwrap().len(), 2);
    }

    #[test]
    fn reads_itunes_library_xml() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>Tracks</key><dict>
  <key>10</key><dict><key>Track ID</key><integer>10</integer><key>Name</key><string>Garota de Ipanema</string><key>Artist</key><string>Tom Jobim</string><key>Total Time</key><integer>191000</integer><key>Loved</key><true/></dict>
  <key>11</key><dict><key>Track ID</key><integer>11</integer><key>Name</key><string>Desafinado</string><key>Artist</key><string>João Gilberto</string></dict>
 </dict>
 <key>Playlists</key><array>
  <dict><key>Name</key><string>Biblioteca</string><key>Master</key><true/><key>Playlist Items</key><array><dict><key>Track ID</key><integer>10</integer></dict></array></dict>
  <dict><key>Name</key><string>Domingo</string><key>Playlist Items</key><array><dict><key>Track ID</key><integer>11</integer></dict><dict><key>Track ID</key><integer>10</integer></dict></array></dict>
 </array>
</dict></plist>"#;
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("Library.xml");
        std::fs::write(&p, xml).unwrap();
        let pls = read_path(&p).unwrap();
        assert_eq!(pls.len(), 2);
        assert!(pls[0].liked && pls[0].entries[0].title == "Garota de Ipanema");
        assert_eq!(pls[1].name, "Domingo");
        assert_eq!(pls[1].entries.len(), 2);
        assert_eq!(pls[1].source, "Apple Music");
    }
}
