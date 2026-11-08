//! "Similares": what in the library (local files and synced servers) shares a
//! genre/tag such as "alternative rock" or "MPB", for the clickable chips of
//! the About bars.
//!
//! Matching is done on the `genre` column (split on `;`, `,`, `/`), with
//! accents, case and punctuation ignored, plus the MusicBrainz genres already
//! cached for artists and albums the user opened. Nothing here touches files.

use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

use crate::db::Db;
use crate::import::norm;

/// A few common spellings of the same genre.
const ALIASES: &[&[&str]] = &[
    &["mpb", "musica popular brasileira", "brazilian popular music"],
    &["hip hop", "hiphop", "hip hop rap"],
    &["r b", "rnb", "rhythm e blues", "rhythm blues"],
    &["electronic", "eletronica", "electronica", "eletronico"],
    &["alternative", "alternativo", "alternativa"],
    &["alternative rock", "rock alternativo", "alt rock"],
    &["brazilian", "brasileiro", "brasileira", "brasil", "brazil"],
    &["brazilian rock", "rock brasileiro", "rock nacional"],
    &["pop rock", "pop rock nacional"],
    &["sertanejo", "sertanejo universitario"],
    &["samba", "samba enredo"],
    &["funk carioca", "funk brasileiro", "baile funk"],
    &["soundtrack", "trilha sonora"],
    &["classical", "classica", "erudita"],
    &["country", "musica country"],
    &["reggae", "reggae nacional"],
    &["gospel", "gospel brasileiro", "musica gospel"],
];

fn canon(s: &str) -> String {
    let n = norm(s);
    for group in ALIASES {
        if group.iter().any(|a| *a == n) {
            return group[0].to_owned();
        }
    }
    n
}

/// Genre parts of one tag value ("Rock; Alternative / Grunge" → 3 parts).
fn parts(genre: &str) -> Vec<String> {
    genre
        .split([';', ',', '/', '|', '\0'])
        .map(canon)
        .filter(|p| !p.is_empty())
        .collect()
}

/// How well one genre value matches the tag: 3 same genre, 2 a narrower one
/// ("rock" → "alternative rock"), 1 a broader one ("alternative rock" → "rock").
pub fn score(tag: &str, genre: &str) -> i64 {
    let t = canon(tag);
    if t.is_empty() {
        return 0;
    }
    let tw: HashSet<&str> = t.split(' ').collect();
    let mut best = 0;
    for p in parts(genre) {
        if p == t {
            return 3;
        }
        let pw: HashSet<&str> = p.split(' ').collect();
        if tw.is_subset(&pw) {
            best = best.max(2);
        } else if pw.is_subset(&tw) && !pw.is_empty() {
            best = best.max(1);
        }
    }
    best
}

/// Cached MusicBrainz genres (`info:<kind>:<norm key>`) → key → genres.
fn cached_genres(db: &Db, kind: &str) -> HashMap<String, Vec<String>> {
    let mut out = HashMap::new();
    let prefix = format!("info:{kind}:");
    let Ok(mut st) = db.conn.prepare("SELECT k, v FROM kv WHERE substr(k, 1, length(?1)) = ?1") else { return out };
    let Ok(rows) = st.query_map([&prefix], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))) else { return out };
    for (k, v) in rows.flatten() {
        let Ok(v) = serde_json::from_str::<Value>(&v) else { continue };
        let g: Vec<String> = v["data"]["genres"].as_array().map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_owned)).collect()).unwrap_or_default();
        if !g.is_empty() {
            out.insert(k[prefix.len()..].to_owned(), g);
        }
    }
    out
}

/// Library matches for a tag, best first. Items of `exclude_artist` (the
/// artist whose page the chip was on) are left out of artists and albums and
/// go last among the songs.
pub struct TagMatches {
    /// (artist id, score)
    pub artists: Vec<(i64, i64)>,
    /// (album id, score)
    pub albums: Vec<(i64, i64)>,
    /// track ids
    pub tracks: Vec<i64>,
    pub track_total: usize,
}

pub fn matches(db: &Db, tag: &str, exclude_artist: Option<i64>, track_limit: usize) -> crate::Result<TagMatches> {
    struct Row {
        id: i64,
        genre: Option<String>,
        album: Option<i64>,
        artist: Option<i64>,
        plays: i64,
        starred: i64,
    }
    let mut st = db.conn.prepare(
        "SELECT t.id, t.genre, t.album_id, a.artist_id, t.play_count, t.starred
         FROM tracks t LEFT JOIN albums a ON a.id = t.album_id WHERE t.dup_of IS NULL",
    )?;
    let rows: Vec<Row> = st
        .query_map([], |r| {
            Ok(Row { id: r.get(0)?, genre: r.get(1)?, album: r.get(2)?, artist: r.get(3)?, plays: r.get(4)?, starred: r.get(5)? })
        })?
        .flatten()
        .collect();

    // MusicBrainz genres of artists/albums already looked up.
    let artist_names: HashMap<String, i64> = db.artists()?.into_iter().map(|a| (norm(&a.name), a.id)).collect();
    let mut artist_bonus: HashMap<i64, i64> = HashMap::new();
    for (key, g) in cached_genres(db, "artist") {
        let s = g.iter().map(|x| score(tag, x)).max().unwrap_or(0);
        if s > 0 {
            if let Some(id) = artist_names.get(&key) {
                artist_bonus.insert(*id, s * 10);
            }
        }
    }
    let mut album_bonus: HashMap<i64, i64> = HashMap::new();
    let cached_albums = cached_genres(db, "album");
    if !cached_albums.is_empty() {
        for a in db.albums()? {
            let key = norm(&format!("{}\u{1f}{}", a.artist.clone().unwrap_or_default(), a.title));
            if let Some(g) = cached_albums.get(&key) {
                let s = g.iter().map(|x| score(tag, x)).max().unwrap_or(0);
                if s > 0 {
                    album_bonus.insert(a.id, s * 10);
                }
            }
        }
    }

    let mut artists: HashMap<i64, i64> = artist_bonus.clone();
    let mut albums: HashMap<i64, i64> = album_bonus.clone();
    let mut tracks: Vec<(i64, i64, i64, bool)> = vec![]; // (score, plays, id, own)
    for r in &rows {
        let mut s = r.genre.as_deref().map(|g| score(tag, g)).unwrap_or(0);
        if s == 0 {
            // Untagged song on an album/artist MusicBrainz files under the tag.
            if r.album.is_some_and(|a| album_bonus.contains_key(&a)) || r.artist.is_some_and(|a| artist_bonus.contains_key(&a)) {
                s = 1;
            }
        }
        if s == 0 {
            continue;
        }
        let own = exclude_artist.is_some() && r.artist == exclude_artist;
        tracks.push((s, r.plays + r.starred * 3, r.id, own));
        if own {
            continue;
        }
        if let Some(a) = r.artist {
            *artists.entry(a).or_default() += s;
        }
        if let Some(a) = r.album {
            *albums.entry(a).or_default() += s;
        }
    }
    if let Some(x) = exclude_artist {
        artists.remove(&x);
        if !album_bonus.is_empty() {
            for a in db.artist_albums(x)? {
                albums.remove(&a.id);
            }
        }
    }
    let mut artists: Vec<(i64, i64)> = artists.into_iter().collect();
    artists.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    let mut albums: Vec<(i64, i64)> = albums.into_iter().collect();
    albums.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    tracks.sort_by(|a, b| a.3.cmp(&b.3).then(b.0.cmp(&a.0)).then(b.1.cmp(&a.1)).then(a.2.cmp(&b.2)));
    let total = tracks.len();
    Ok(TagMatches {
        artists,
        albums,
        tracks: tracks.into_iter().take(track_limit).map(|t| t.2).collect(),
        track_total: total,
    })
}

/// Artists tagged with `tag` on MusicBrainz (most relevant first), for the
/// "Para descobrir" row. With `area` (e.g. "Brazil"), artists from there come
/// first, so a Brazilian band's "rock" chip shows Brazilian rock bands.
pub fn fetch_tag_artists(tag: &str, area: Option<&str>) -> Option<Value> {
    let mut out: Vec<Value> = vec![];
    let mut seen = HashSet::new();
    let mut queries = vec![];
    if let Some(a) = area.filter(|a| !a.is_empty()) {
        queries.push(format!("tag:{} AND area:{}", crate::info::mb_phrase(&tag.to_lowercase()), crate::info::mb_phrase(a)));
    }
    queries.push(format!("tag:{}", crate::info::mb_phrase(&tag.to_lowercase())));
    let mut any = false;
    for q in queries {
        let Some(r) = crate::info::mb_search("artist", &q, 40) else { continue };
        any = true;
        for h in r["artists"].as_array().into_iter().flatten() {
            let Some(id) = h["id"].as_str() else { continue };
            if !seen.insert(id.to_owned()) {
                continue;
            }
            let name = h["name"].as_str().unwrap_or("").to_owned();
            if name.is_empty() {
                continue;
            }
            out.push(json!({
                "name": name,
                "type": crate::info::artist_type(h["type"].as_str().unwrap_or("")),
                "area": h["area"]["name"].as_str().unwrap_or(""),
                "disambiguation": h["disambiguation"].as_str().unwrap_or(""),
                "link": format!("https://musicbrainz.org/artist/{id}"),
            }));
        }
    }
    any.then(|| json!({ "artists": out }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scores() {
        assert_eq!(score("alternative rock", "Alternative Rock"), 3);
        assert_eq!(score("MPB", "Música Popular Brasileira"), 3);
        assert_eq!(score("Rock", "Alternative Rock; Pop"), 2);
        assert_eq!(score("alternative rock", "Rock"), 1);
        assert_eq!(score("Brazilian", "Rock Brasileiro"), 2);
        assert_eq!(score("Brazilian rock", "Rock Brasileiro"), 3);
        assert_eq!(score("Hip-Hop", "hip hop"), 3);
        assert_eq!(score("jazz", "Rock"), 0);
        assert_eq!(score("", "Rock"), 0);
    }
}
