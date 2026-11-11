//! Library browsing: search with field filters, sort orders, groupings
//! (genre, year, composer, folder) and "autoplay" picks.
//!
//! Search syntax (accents and case don't matter):
//!   `kanye`                    free text over title/artist/album (prefix match)
//!   `artista:kanye`            contains; `artista:"Kanye West"` is exact
//!   `album:` `genero:` `compositor:` `titulo:` `pasta:"/path"` (prefix)
//!   `ano:2021` or `ano:2010-2019`, `fav:sim`
//!   `letra:"eu sei que vou"`   words of the saved lyrics (see lyricsearch.rs)
//! Filters combine with AND and with the free text.

use rusqlite::types::Value;
use std::collections::HashSet;

use crate::db::{map_track, Db, TrackRow, TRACK_COLS};
use crate::Result;

#[derive(Debug, Default, PartialEq)]
pub struct Query {
    pub text: Vec<String>,
    /// (column, value, exact)
    pub fields: Vec<(Field, String, bool)>,
    pub years: Option<(i64, i64)>,
    pub starred: bool,
    /// `letra:` words (folded), matched against the saved lyrics.
    pub lyrics: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Field {
    Title,
    Artist,
    Album,
    Genre,
    Composer,
    Folder,
}

fn fold(s: &str) -> String {
    use unicode_normalization::UnicodeNormalization;
    s.nfd().filter(|c| !unicode_normalization::char::is_combining_mark(*c)).collect::<String>().to_lowercase()
}

/// Split into tokens, keeping `key:"quoted value"` and `"quoted"` together.
fn tokens(q: &str) -> Vec<(String, bool)> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut quoted = false;
    let mut had_quote = false;
    for c in q.chars() {
        match c {
            '"' => {
                quoted = !quoted;
                had_quote = true;
            }
            c if c.is_whitespace() && !quoted => {
                if !cur.is_empty() {
                    out.push((std::mem::take(&mut cur), had_quote));
                }
                had_quote = false;
            }
            c => cur.push(c),
        }
    }
    if !cur.is_empty() {
        out.push((cur, had_quote));
    }
    out
}

pub fn parse(q: &str) -> Query {
    let mut out = Query::default();
    for (tok, quoted) in tokens(q) {
        let Some((k, v)) = tok.split_once(':') else {
            out.text.push(tok);
            continue;
        };
        let v = v.trim().to_owned();
        let field = match fold(k).as_str() {
            "artista" | "artist" | "art" => Some(Field::Artist),
            "album" | "alb" => Some(Field::Album),
            "genero" | "genre" | "gen" => Some(Field::Genre),
            "compositor" | "composer" => Some(Field::Composer),
            "titulo" | "title" | "musica" => Some(Field::Title),
            "pasta" | "folder" => Some(Field::Folder),
            "ano" | "year" => {
                let (a, b) = v.split_once('-').unwrap_or((&v, &v));
                if let (Ok(a), Ok(b)) = (a.trim().parse::<i64>(), b.trim().parse::<i64>()) {
                    out.years = Some((a.min(b), a.max(b)));
                }
                continue;
            }
            "letra" | "lyrics" | "lyric" => {
                out.lyrics.extend(crate::lyricsearch::query_words(&v));
                continue;
            }
            "fav" | "favorita" | "favoritas" => {
                out.starred = !matches!(fold(&v).as_str(), "nao" | "no" | "0");
                continue;
            }
            _ => None,
        };
        match field {
            Some(f) if !v.is_empty() => out.fields.push((f, v, quoted)),
            Some(_) => {}
            None => out.text.push(tok),
        }
    }
    out
}

/// Sort orders offered by the "Músicas" page.
pub fn order_by(sort: &str) -> &'static str {
    match sort {
        "title" => "t.title COLLATE NATSORT, t.artist COLLATE NATSORT",
        "album" => "a.title IS NULL, a.title COLLATE NATSORT, t.disc_no, t.track_no, t.title COLLATE NATSORT",
        "added" => "t.added_at DESC, a.title COLLATE NATSORT, t.disc_no, t.track_no",
        "year" => "COALESCE(t.year, a.year) IS NULL, COALESCE(t.year, a.year) DESC, a.title COLLATE NATSORT, t.disc_no, t.track_no",
        "plays" => "t.play_count DESC, t.last_played DESC, t.title COLLATE NATSORT",
        "duration" => "t.duration_ms DESC",
        _ => "t.artist COLLATE NATSORT, a.year, a.title COLLATE NATSORT, t.disc_no, t.track_no",
    }
}

#[derive(Debug, Clone)]
pub struct GroupRow {
    /// Value to filter by (for folders, the full path).
    pub key: String,
    pub name: String,
    pub detail: String,
    pub count: i64,
    pub cover_hash: Option<String>,
}

impl Db {
    /// Search + filters + sort. An empty query with no filters lists the whole library.
    pub fn query_tracks(&self, q: &str, sort: &str, limit: i64) -> Result<Vec<TrackRow>> {
        self.query_tracks_ext(q, sort, limit, false)
    }

    /// Like [`Db::query_tracks`]; with `with_lyrics` the free text also finds
    /// songs by the words of their saved lyrics (the search bar does this,
    /// saved searches don't). Title/artist/album hits come first.
    pub fn query_tracks_ext(&self, q: &str, sort: &str, limit: i64, with_lyrics: bool) -> Result<Vec<TrackRow>> {
        let p = parse(q);
        let mut sql = format!("SELECT {TRACK_COLS} FROM tracks t LEFT JOIN albums a ON a.id = t.album_id");
        let mut wh: Vec<String> = vec!["t.dup_of IS NULL".into()];
        let mut args: Vec<Value> = Vec::new();
        let mut rank: Option<&str> = None;
        if !p.text.is_empty() {
            let fts = p
                .text
                .iter()
                .map(|w| format!("\"{}\"*", w.replace('"', "")))
                .collect::<Vec<_>>()
                .join(" ");
            let words = crate::lyricsearch::query_words(&p.text.join(" "));
            if with_lyrics && crate::lyricsearch::long_enough(&words) {
                args.push(Value::Text(fts));
                args.push(Value::Text(crate::lyricsearch::fts_query(&words)));
                let (m, l) = (args.len() - 1, args.len());
                sql.push_str(&format!(
                    " LEFT JOIN (SELECT rowid AS id, rank AS r FROM tracks_fts WHERE tracks_fts MATCH ?{m}) fm ON fm.id = t.id
                      LEFT JOIN (SELECT rowid AS id, rank AS r FROM lyrics_fts WHERE lyrics_fts MATCH ?{l}) fl ON fl.id = t.id"
                ));
                wh.push("(fm.id IS NOT NULL OR fl.id IS NOT NULL)".into());
                rank = Some("fm.id IS NULL, fm.r, fl.r");
            } else {
                sql.push_str(" JOIN tracks_fts f ON f.rowid = t.id");
                args.push(Value::Text(fts));
                wh.push(format!("tracks_fts MATCH ?{}", args.len()));
                rank = Some("rank");
            }
        }
        if !p.lyrics.is_empty() {
            args.push(Value::Text(crate::lyricsearch::fts_query(&p.lyrics)));
            sql.push_str(&format!(
                " JOIN (SELECT rowid AS id, rank AS r FROM lyrics_fts WHERE lyrics_fts MATCH ?{}) lx ON lx.id = t.id",
                args.len()
            ));
            rank = Some(match rank {
                None => "lx.r",
                Some("rank") => "f.rank, lx.r",
                Some(r) => r,
            });
        }
        for (f, v, exact) in &p.fields {
            let col = match f {
                Field::Title => "t.title",
                Field::Artist => "(t.artist || ' ' || COALESCE((SELECT name FROM artists WHERE id = a.artist_id), ''))",
                Field::Album => "a.title",
                Field::Genre => "t.genre",
                Field::Composer => "t.composer",
                Field::Folder => {
                    args.push(Value::Text(v.clone()));
                    wh.push(format!("substr(t.path, 1, length(?{0})) = ?{0}", args.len()));
                    continue;
                }
            };
            if *exact && *f != Field::Artist {
                args.push(Value::Text(v.clone()));
                wh.push(format!("{col} = ?{} COLLATE NOCASE", args.len()));
            } else if *exact {
                args.push(Value::Text(v.clone()));
                wh.push(format!("(t.artist = ?{0} COLLATE NOCASE OR a.artist_id = (SELECT id FROM artists WHERE name = ?{0}))", args.len()));
            } else {
                args.push(Value::Text(format!("%{}%", v.replace('%', "").replace('_', ""))));
                wh.push(format!("{col} LIKE ?{}", args.len()));
            }
        }
        if let Some((a, b)) = p.years {
            args.push(Value::Integer(a));
            args.push(Value::Integer(b));
            wh.push(format!("COALESCE(t.year, a.year) BETWEEN ?{} AND ?{}", args.len() - 1, args.len()));
        }
        if p.starred {
            wh.push("t.starred = 1".into());
        }
        {
            sql.push_str(" WHERE ");
            sql.push_str(&wh.join(" AND "));
        }
        let order = match rank {
            Some(r) if sort.is_empty() => r,
            _ => order_by(sort),
        };
        sql.push_str(&format!(" ORDER BY {order}"));
        if limit > 0 {
            sql.push_str(&format!(" LIMIT {limit}"));
        }
        let mut st = self.conn.prepare(&sql)?;
        let rows = st.query_map(rusqlite::params_from_iter(args), map_track)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Categories for the sidebar: "genre", "year", "composer" or "folder".
    pub fn groups(&self, kind: &str) -> Result<Vec<GroupRow>> {
        let cover = "MAX(COALESCE(a.cover_hash, t.cover_hash))";
        let from = "FROM tracks t LEFT JOIN albums a ON a.id = t.album_id";
        let from = &format!("{from} WHERE t.dup_of IS NULL AND");
        let sql = match kind {
            "genre" => format!("SELECT t.genre, COUNT(*), {cover} {from} t.genre IS NOT NULL AND t.genre != '' GROUP BY t.genre COLLATE NOCASE ORDER BY t.genre COLLATE NATSORT"),
            "composer" => format!("SELECT t.composer, COUNT(*), {cover} {from} t.composer IS NOT NULL AND t.composer != '' GROUP BY t.composer COLLATE NOCASE ORDER BY t.composer COLLATE NATSORT"),
            "year" => format!("SELECT CAST(COALESCE(t.year, a.year) AS TEXT), COUNT(*), {cover} {from} COALESCE(t.year, a.year) > 0 GROUP BY COALESCE(t.year, a.year) ORDER BY COALESCE(t.year, a.year) DESC"),
            "folder" => return self.folder_groups(),
            _ => return Ok(vec![]),
        };
        let mut st = self.conn.prepare(&sql)?;
        let rows = st.query_map([], |r| {
            let k: String = r.get(0)?;
            let n: i64 = r.get(1)?;
            Ok(GroupRow {
                name: k.clone(),
                key: k,
                detail: if n == 1 { "1 música".into() } else { format!("{n} músicas") },
                count: n,
                cover_hash: r.get(2)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Folders that directly contain music (local files only).
    fn folder_groups(&self) -> Result<Vec<GroupRow>> {
        let mut st = self.conn.prepare(
            "SELECT t.path, COALESCE(a.cover_hash, t.cover_hash) FROM tracks t LEFT JOIN albums a ON a.id = t.album_id
             WHERE t.path NOT LIKE 'remote://%' AND t.dup_of IS NULL",
        )?;
        let mut map: std::collections::BTreeMap<String, (i64, Option<String>)> = Default::default();
        for r in st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)))? {
            let (path, cover) = r?;
            let dir = std::path::Path::new(&path).parent().map(|d| d.to_string_lossy().into_owned()).unwrap_or_default();
            let e = map.entry(dir).or_insert((0, None));
            e.0 += 1;
            if e.1.is_none() {
                e.1 = cover;
            }
        }
        let mut out: Vec<GroupRow> = map
            .into_iter()
            .map(|(dir, (n, cover))| {
                let name = std::path::Path::new(&dir)
                    .file_name()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_else(|| dir.clone());
                GroupRow {
                    key: format!("{dir}/"),
                    name,
                    detail: format!("{} · {}", if n == 1 { "1 música".to_string() } else { format!("{n} músicas") }, dir),
                    count: n,
                    cover_hash: cover,
                }
            })
            .collect();
        out.sort_by(|a, b| crate::natural::natural_cmp(&a.name, &b.name));
        Ok(out)
    }

    /// Up to `n` tracks to keep playing after the queue ends: same artist and
    /// genre first, then favourites and most played, then anything — never
    /// one of `exclude`, and in random order within each pool.
    pub fn autoplay(&self, seed: i64, exclude: &HashSet<i64>, n: usize) -> Result<Vec<TrackRow>> {
        let seed_row = self.track(seed)?;
        let (artist, genre) = seed_row
            .as_ref()
            .map(|t| (t.artist.clone(), t.genre.clone().unwrap_or_default()))
            .unwrap_or_default();
        let pools: [(&str, Vec<Value>); 4] = [
            ("t.artist = ?1 COLLATE NOCASE", vec![Value::Text(artist)]),
            ("t.genre = ?1 COLLATE NOCASE AND t.genre != ''", vec![Value::Text(genre)]),
            ("(t.starred = 1 OR t.play_count > 1)", vec![]),
            ("1", vec![]),
        ];
        let quotas = [n / 4 + 1, n / 3 + 1, n / 4 + 1, n];
        let mut seen = exclude.clone();
        seen.insert(seed);
        let mut out = Vec::new();
        for ((clause, args), quota) in pools.into_iter().zip(quotas) {
            if out.len() >= n {
                break;
            }
            let sql = format!(
                "SELECT {TRACK_COLS} FROM tracks t LEFT JOIN albums a ON a.id = t.album_id WHERE t.dup_of IS NULL AND {clause} ORDER BY random() LIMIT {}",
                quota + seen.len().min(400)
            );
            let mut st = self.conn.prepare(&sql)?;
            let rows: Vec<TrackRow> = st
                .query_map(rusqlite::params_from_iter(args), map_track)?
                .collect::<std::result::Result<_, _>>()?;
            let mut taken = 0;
            for r in rows {
                if taken >= quota || out.len() >= n {
                    break;
                }
                if seen.insert(r.id) {
                    out.push(r);
                    taken += 1;
                }
            }
        }
        // Interleave so the same artist doesn't play many times in a row.
        let mut mixed: Vec<TrackRow> = Vec::with_capacity(out.len());
        let mut rest = out;
        while !rest.is_empty() {
            let last = mixed.last().map(|t: &TrackRow| t.artist.clone());
            let i = rest.iter().position(|t| Some(&t.artist) != last.as_ref()).unwrap_or(0);
            mixed.push(rest.remove(i));
        }
        Ok(mixed)
    }
}

/// Index letter for a row under a sort order ("A".."Z", "#", or a year), used by
/// the A–Z bar and the scroll bubble. Empty when the order has no sections.
pub fn section_of(t: &TrackRow, sort: &str) -> String {
    let key = match sort {
        "title" => t.title.as_str(),
        "album" => t.album.as_deref().unwrap_or(""),
        "year" => return t.year.map(|y| y.to_string()).unwrap_or_else(|| "—".into()),
        "" | "artist" => t.artist.as_str(),
        _ => return String::new(),
    };
    letter(key)
}

pub fn letter(key: &str) -> String {
    let skip = |c: char| !c.is_alphanumeric();
    let c = fold(key.trim_start_matches(skip)).chars().next();
    match c {
        Some(c) if c.is_ascii_alphabetic() => c.to_ascii_uppercase().to_string(),
        _ => "#".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{upsert_track, NewTrack};

    #[test]
    fn parses_filters() {
        let q = parse("love artista:\"Kanye West\" gênero:rap ano:2010-2019 fav:sim");
        assert_eq!(q.text, vec!["love"]);
        assert_eq!(q.fields, vec![(Field::Artist, "Kanye West".into(), true), (Field::Genre, "rap".into(), false)]);
        assert_eq!(q.years, Some((2010, 2019)));
        assert!(q.starred);
        assert_eq!(parse("ano:1999").years, Some((1999, 1999)));
        assert_eq!(parse("a:b").text, vec!["a:b"]);
    }

    #[test]
    fn letters() {
        assert_eq!(letter("Ébano"), "E");
        assert_eq!(letter("  'Round Midnight"), "R");
        assert_eq!(letter("2Pac"), "#");
        assert_eq!(letter(""), "#");
    }

    fn sample() -> Db {
        let db = Db::open_in_memory().unwrap();
        let rows = [
            ("/m/rock/a.mp3", "Alpha", "Banda X", Some("Disco 1"), Some(1999), Some("Rock")),
            ("/m/rock/b.mp3", "Beta", "Banda X", Some("Disco 1"), Some(1999), Some("Rock")),
            ("/m/rap/c.mp3", "Gamma", "MC Y", None, Some(2015), Some("Rap")),
            ("/m/rap/d.mp3", "Delta", "MC Y", None, None, Some("Trap")),
        ];
        for (i, (p, t, ar, al, y, g)) in rows.iter().enumerate() {
            upsert_track(
                &db.conn,
                &NewTrack {
                    path: p, mtime: 100 + i as i64, size: 1, title: t, artist: ar, album_artist: ar,
                    album: *al, track_no: Some(i as u32 + 1), disc_no: None, year: *y, duration_ms: 1000,
                    track_gain: None, album_gain: None, cover_hash: None, genre: *g, composer: None, format: None, sample_rate: None, bit_depth: None, bitrate: None, explicit: None, art_hash: None, folder_art: None,
                },
                0,
            )
            .unwrap();
        }
        db
    }

    #[test]
    fn finds_songs_by_their_lyrics() {
        let db = sample();
        // ids follow insertion: Alpha 1, Beta 2, Gamma 3, Delta 4
        db.store_lyrics(2, "lrclib", Some("[00:01.00]Eu sei que vou te amar\n[00:04.00]Por toda a minha vida"), None, 0).unwrap();
        db.store_lyrics(3, "user", None, Some("Coração de estudante\nAlpha e ômega"), 0).unwrap();
        let titles = |q: &str, lyr: bool| {
            db.query_tracks_ext(q, "", 0, lyr).unwrap().into_iter().map(|t| t.title).collect::<Vec<_>>()
        };
        assert_eq!(titles("vou te am", true), vec!["Beta"]);
        assert_eq!(titles("coracao", true), vec!["Gamma"]);
        // Title hits first, then lyric hits.
        assert_eq!(titles("alpha", true), vec!["Alpha", "Gamma"]);
        // Saved searches (smart playlists) keep matching only title/artist/album…
        assert_eq!(titles("alpha", false), vec!["Alpha"]);
        // …unless they say letra:.
        assert_eq!(titles("letra:\"minha vida\"", false), vec!["Beta"]);
        assert_eq!(titles("letra:alpha artista:\"MC Y\"", false), vec!["Gamma"]);
        // Edited lyrics replace the old words; forgotten lyrics stop matching.
        db.store_lyrics(2, "user", None, Some("outra letra"), 0).unwrap();
        assert!(titles("vou te am", true).is_empty());
        db.delete_lyrics(3).unwrap();
        assert!(titles("coracao", true).is_empty());
        // Too short to search the words of every song.
        assert!(titles("e", true).is_empty());
    }

    #[test]
    fn indexes_lyrics_saved_before() {
        let db = sample();
        db.conn.execute("INSERT INTO lyrics(track_id, source, plain, fetched_at) VALUES (1, 'lrclib', 'velha canção', 0)", []).unwrap();
        db.conn.execute("INSERT INTO lyrics(track_id, source, fetched_at) VALUES (2, 'none', 0)", []).unwrap();
        assert!(db.query_tracks_ext("cancao", "", 0, true).unwrap().is_empty());
        assert_eq!(db.index_lyrics_backlog().unwrap(), 1);
        assert_eq!(db.query_tracks_ext("cancao", "", 0, true).unwrap()[0].title, "Alpha");
        assert_eq!(db.index_lyrics_backlog().unwrap(), 0);
    }

    #[test]
    fn filters_sorts_and_groups() {
        let db = sample();
        let titles = |q: &str, s: &str| db.query_tracks(q, s, 0).unwrap().into_iter().map(|t| t.title).collect::<Vec<_>>();
        assert_eq!(titles("genero:rap", "title"), vec!["Delta", "Gamma"]); // contains: Rap, Trap
        assert_eq!(titles("genero:\"rap\"", "title"), vec!["Gamma"]);
        assert_eq!(titles("ano:1990-2000", "title"), vec!["Alpha", "Beta"]);
        assert_eq!(titles("pasta:\"/m/rap/\"", "title"), vec!["Delta", "Gamma"]);
        assert_eq!(titles("artista:\"MC Y\" gam", ""), vec!["Gamma"]);
        assert_eq!(titles("", "added"), vec!["Delta", "Gamma", "Beta", "Alpha"]);
        let g = db.groups("genre").unwrap();
        assert_eq!(g.iter().map(|g| (g.name.as_str(), g.count)).collect::<Vec<_>>(), vec![("Rap", 1), ("Rock", 2), ("Trap", 1)]);
        let f = db.groups("folder").unwrap();
        assert_eq!(f.iter().map(|g| g.key.as_str()).collect::<Vec<_>>(), vec!["/m/rap/", "/m/rock/"]);
        assert_eq!(db.groups("year").unwrap()[0].name, "2015");
    }

    #[test]
    fn autoplay_prefers_same_artist_and_skips_excluded() {
        let db = sample();
        let all = db.query_tracks("", "title", 0).unwrap();
        let id = |t: &str| all.iter().find(|r| r.title == t).unwrap().id;
        let picks = db.autoplay(id("Alpha"), &HashSet::from([id("Gamma")]), 2).unwrap();
        assert_eq!(picks.len(), 2);
        assert!(picks.iter().any(|t| t.title == "Beta"));
        assert!(picks.iter().all(|t| t.title != "Gamma" && t.title != "Alpha"));
    }
}
