//! Incremental, parallel library scanner.
//!
//! Differences from Nocturne's approach:
//! * Only files whose (mtime, size) changed since the last scan are parsed.
//! * Tag parsing runs on a rayon pool; *writes* happen on one thread in a
//!   single transaction (SQLite is fastest that way).
//! * Embedded covers are decoded once **per album**, shrunk to a small JPEG
//!   thumbnail on disk, and never kept in RAM. The UI loads thumbnails lazily
//!   for visible items only.

use lofty::file::{AudioFile, TaggedFileExt};
use lofty::tag::{Accessor, ItemKey};
use rayon::prelude::*;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

use crate::covers::CoverCache;
use crate::db::Db;
use crate::Result;

pub const AUDIO_EXTENSIONS: &[&str] = &[
    "mp3", "flac", "ogg", "oga", "opus", "m4a", "mp4", "aac", "wav", "wv", "ape", "aiff", "aif",
];

#[derive(Debug, Default, Clone)]
pub struct ScanStats {
    pub seen: usize,
    pub parsed: usize,
    pub unchanged: usize,
    pub removed: usize,
    pub failed: usize,
    pub covers_written: usize,
    pub elapsed_ms: u128,
}

/// Progress callback events (UI can show "Indexando 1200/5000").
#[derive(Debug, Clone)]
pub enum ScanEvent {
    Discovered(usize),
    Parsed { done: usize, total: usize },
    Finished(ScanStats),
}

struct Parsed {
    path: String,
    mtime: i64,
    size: i64,
    title: String,
    artist: String,
    album_artist: String,
    album: Option<String>,
    track_no: Option<u32>,
    disc_no: Option<u32>,
    year: Option<u32>,
    duration_ms: u64,
    track_gain: Option<f64>,
    album_gain: Option<f64>,
    genre: Option<String>,
    composer: Option<String>,
    format: Option<String>,
    sample_rate: Option<u32>,
    bit_depth: Option<u8>,
    bitrate: Option<u32>,
    explicit: Option<bool>,
    /// Own picture of a track without an album.
    cover_hash: Option<String>,
    /// Embedded front cover and folder art; the album cover is voted from these.
    art_hash: Option<String>,
    folder_art: Option<String>,
}

/// Folder art (cover.jpg, folder.png…) per directory, looked up once and
/// shared by the parser threads.
pub struct FolderArt {
    dirs: std::sync::Mutex<HashMap<PathBuf, Option<String>>>,
}

impl FolderArt {
    fn new() -> Self {
        Self { dirs: Default::default() }
    }
    fn hash_for(&self, dir: &Path, covers: &CoverCache) -> Option<String> {
        if let Some(h) = self.dirs.lock().unwrap().get(dir) {
            return h.clone();
        }
        let h = folder_cover(dir).and_then(|f| std::fs::read(f).ok()).and_then(|b| covers.store(&b).ok());
        self.dirs.lock().unwrap().insert(dir.to_path_buf(), h.clone());
        h
    }
}

/// The picture that stands for the record: the one tagged "front cover",
/// else the first one (many taggers don't set a type).
fn front_picture(t: &lofty::tag::Tag) -> Option<&lofty::picture::Picture> {
    t.pictures()
        .iter()
        .find(|p| p.pic_type() == lofty::picture::PictureType::CoverFront)
        .or_else(|| t.pictures().first())
}

fn is_audio(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| AUDIO_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

fn file_sig(p: &Path) -> Option<(i64, i64)> {
    let md = std::fs::metadata(p).ok()?;
    let mtime = md
        .modified()
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_secs() as i64;
    Some((mtime, md.len() as i64))
}

/// Track (and disc) number written at the start of a file name, used when the
/// tags have none: "09 - Song", "09. Song", "1-09 Song", "2.03_Song", "(07) Song".
/// A bare number needs a separator after it ("99 Luftballons" is a title,
/// "09 Song" with a leading zero is a track).
pub fn number_from_filename(stem: &str) -> Option<(Option<u32>, u32)> {
    let s = stem.trim_start().trim_start_matches(['(', '[']);
    let digits = |s: &str| s.bytes().take_while(u8::is_ascii_digit).count();
    let n1 = digits(s);
    if n1 == 0 || n1 > 3 {
        return None;
    }
    let (first, rest) = s.split_at(n1);
    // "1-09" / "2.03": a one-digit disc, then a two- or three-digit track.
    if n1 == 1 {
        if let Some(r) = rest.strip_prefix(['-', '.']) {
            let n2 = digits(r);
            if (2..=3).contains(&n2) {
                let (second, tail) = r.split_at(n2);
                if tail.is_empty() || tail.starts_with([' ', '-', '.', '_', ')', ']']) {
                    let (d, t): (u32, u32) = (first.parse().ok()?, second.parse().ok()?);
                    return (d > 0 && t > 0).then_some((Some(d), t));
                }
            }
        }
    }
    let after = rest.trim_start();
    let separated = after.starts_with(['.', '-', '_', ')', ']', '–'])
        || (after.len() < rest.len() && first.starts_with('0'))
        || (rest.is_empty());
    let t: u32 = first.parse().ok()?;
    (separated && t > 0).then_some((None, t))
}

fn parse_gain(s: Option<&str>) -> Option<f64> {
    s?.trim().trim_end_matches("dB").trim().parse().ok()
}

fn parse_file(
    path: &Path,
    mtime: i64,
    size: i64,
    folders: &FolderArt,
    covers: &CoverCache,
) -> Option<Parsed> {
    let tagged = lofty::read_from_path(path).ok()?;
    let props = tagged.properties();
    let duration_ms = props.duration().as_millis() as u64;
    let format = Some(match tagged.file_type() {
        lofty::file::FileType::Flac => "FLAC",
        lofty::file::FileType::Mpeg => "MP3",
        lofty::file::FileType::Opus => "Opus",
        lofty::file::FileType::Vorbis => "Vorbis",
        lofty::file::FileType::Mp4 => {
            // ALAC and AAC share the container; ALAC reports a bit depth.
            if props.bit_depth().is_some() { "ALAC" } else { "AAC" }
        }
        lofty::file::FileType::Wav => "WAV",
        lofty::file::FileType::Aiff => "AIFF",
        lofty::file::FileType::WavPack => "WavPack",
        lofty::file::FileType::Ape => "APE",
        lofty::file::FileType::Aac => "AAC",
        _ => "",
    })
    .filter(|f| !f.is_empty())
    .map(str::to_owned);
    let (sample_rate, bit_depth, bitrate) = (props.sample_rate(), props.bit_depth(), props.audio_bitrate());
    let tag = tagged.primary_tag().or_else(|| tagged.first_tag());

    let stem = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();

    // Parental advisory: iTunes rtng / ITUNESADVISORY (lofty maps both to
    // ParentalAdvisory; Vorbis comments keep ITUNESADVISORY as an unknown key),
    // or a plain EXPLICIT / CONTENTRATING field.
    let explicit = tag.and_then(|t| {
        t.get_string(&ItemKey::ParentalAdvisory)
            .and_then(crate::explicit::from_tag_value)
            .or_else(|| {
                ["ITUNESADVISORY", "EXPLICIT", "CONTENTRATING", "CONTENT RATING", "ADVISORY"].iter().find_map(|k| {
                    t.get_string(&ItemKey::Unknown((*k).to_string())).and_then(crate::explicit::from_tag_value)
                })
            })
    });

    let mut art: Option<String> = None;
    let folder_art = path.parent().and_then(|d| folders.hash_for(d, covers));
    let (title, artist, album_artist, album, track_no, disc_no, year, tg, ag, picture, genre, composer) =
        match tag {
            Some(t) => {
                let artist = t.artist().map(|s| s.into_owned()).unwrap_or_default();
                let album_artist = t
                    .get_string(&ItemKey::AlbumArtist)
                    .map(str::to_owned)
                    .unwrap_or_else(|| artist.clone());
                let album_s = t.album().map(|s| s.into_owned()).unwrap_or_default();
                // Every file records its own picture (one decode per distinct
                // image, the cache dedupes by hash); the album cover is voted
                // afterwards from all of them, see db::pick_album_covers.
                art = front_picture(t).and_then(|pic| covers.store(pic.data()).ok());
                let picture = if album_s.is_empty() { art.clone() } else { None };
                (
                    t.title().map(|s| s.into_owned()).unwrap_or_else(|| stem.clone()),
                    artist,
                    album_artist,
                    t.album().map(|s| s.into_owned()).filter(|s| !s.is_empty()),
                    t.track(),
                    t.disk(),
                    t.year(),
                    parse_gain(t.get_string(&ItemKey::ReplayGainTrackGain)),
                    parse_gain(t.get_string(&ItemKey::ReplayGainAlbumGain)),
                    picture,
                    t.genre().map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()),
                    t.get_string(&ItemKey::Composer).map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()),
                )
            }
            None => (stem.clone(), String::new(), String::new(), None, None, None, None, None, None, None, None, None),
        };
    // Untagged numbers come from the file name, so an album with missing
    // songs still shows (and sorts by) the real track numbers.
    let from_name = if track_no.is_none() { number_from_filename(&stem) } else { None };
    let track_no = track_no.or(from_name.map(|(_, t)| t));
    let disc_no = disc_no.or(from_name.and_then(|(d, _)| d));

    // Store titles like "Song (Explicit)" or "Song [Explicit Version]".
    let explicit = explicit.or_else(|| {
        let l = title.to_lowercase();
        (l.contains("(explicit") || l.contains("[explicit") || l.contains("(explícit")).then_some(true)
    });

    Some(Parsed {
        explicit,
        path: path.to_string_lossy().into_owned(),
        mtime,
        size,
        title,
        artist,
        album_artist,
        album,
        track_no,
        disc_no,
        year,
        duration_ms,
        track_gain: tg,
        album_gain: ag,
        cover_hash: picture,
        art_hash: art,
        folder_art,
        genre,
        composer,
        format,
        sample_rate,
        bit_depth,
        bitrate,
    })
}

/// Look for folder art next to the file (cover.jpg, folder.png, ...). When
/// several exist, the name order below decides, not the directory order.
fn folder_cover(dir: &Path) -> Option<PathBuf> {
    const NAMES: &[&str] = &["cover", "folder", "front", "album"];
    let rd = std::fs::read_dir(dir).ok()?;
    rd.flatten()
        .filter_map(|e| {
            let p = e.path();
            let stem = p.file_stem()?.to_string_lossy().to_ascii_lowercase();
            let ext = p.extension()?.to_string_lossy().to_ascii_lowercase();
            let rank = NAMES.iter().position(|n| *n == stem)?;
            matches!(ext.as_str(), "jpg" | "jpeg" | "png").then_some((rank, p))
        })
        .min()
        .map(|(_, p)| p)
}

/// "root" with a trailing separator, so /music doesn't match /music2.
fn root_prefix(root: &Path) -> String {
    let mut s = root.to_string_lossy().into_owned();
    if !s.ends_with(std::path::MAIN_SEPARATOR) {
        s.push(std::path::MAIN_SEPARATOR);
    }
    s
}

/// A music folder that can be read right now and isn't an empty mount point
/// (a locked or unplugged external disk leaves either nothing or an empty dir).
pub fn root_available(root: &Path) -> bool {
    std::fs::read_dir(root).map(|mut it| it.next().is_some()).unwrap_or(false)
}

pub fn scan(
    db: &mut Db,
    covers: &CoverCache,
    roots: &[PathBuf],
    mut on_event: impl FnMut(ScanEvent),
) -> Result<ScanStats> {
    let _writer = crate::db::WRITER.lock().unwrap_or_else(|e| e.into_inner());
    let t0 = Instant::now();
    let mut stats = ScanStats::default();
    let known = db.known_files()?;

    // 1. Walk (cheap: stat only).
    let mut found: Vec<(PathBuf, i64, i64)> = Vec::new();
    // Roots we could not read completely (locked or unplugged external disk,
    // unmounted mount point, I/O errors): their tracks are kept as they are.
    let mut unreliable: Vec<String> = Vec::new();
    for root in roots {
        let before = found.len();
        let mut errors = false;
        for e in WalkDir::new(root)
            .follow_links(true)
            .into_iter()
            .filter_entry(|e| e.depth() == 0 || !e.file_name().to_string_lossy().starts_with('.'))
        {
            let e = match e {
                Ok(e) => e,
                Err(_) => {
                    errors = true;
                    continue;
                }
            };
            if e.file_type().is_file() && is_audio(e.path()) {
                if let Some((m, s)) = file_sig(e.path()) {
                    found.push((e.into_path(), m, s));
                }
            }
        }
        if errors || found.len() == before {
            log::info!("{} unavailable or empty: keeping its tracks", root.display());
            unreliable.push(root_prefix(root));
        }
    }
    stats.seen = found.len();
    on_event(ScanEvent::Discovered(found.len()));

    let seen_paths: HashSet<String> =
        found.iter().map(|(p, _, _)| p.to_string_lossy().into_owned()).collect();

    let to_parse: Vec<_> = found
        .into_iter()
        .filter(|(p, m, s)| known.get(p.to_string_lossy().as_ref()) != Some(&(*m, *s)))
        .collect();
    stats.unchanged = stats.seen - to_parse.len();

    // 2. Parse in parallel, write in batches from this thread.
    let total = to_parse.len();
    let (tx, rx) = crossbeam_channel::bounded::<Option<Parsed>>(64);
    let folders = FolderArt::new();
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as i64;

    std::thread::scope(|s| -> Result<()> {
        let folders = &folders;
        s.spawn(move || {
            to_parse.par_iter().for_each_with(tx, |tx, (p, m, sz)| {
                let parsed = parse_file(p, *m, *sz, folders, covers);
                let _ = tx.send(parsed);
            });
        });

        // Commit in small batches so the write lock is released often: the UI
        // (saving the queue, play counts, stars) never waits more than a moment.
        let mut txn = db.conn.unchecked_transaction()?;
        let mut batch_start = Instant::now();
        let mut done = 0usize;
        for msg in rx {
            done += 1;
            let Some(p) = msg else {
                stats.failed += 1;
                continue;
            };
            stats.parsed += 1;

            crate::db::upsert_track(
                &txn,
                &crate::db::NewTrack {
                    path: &p.path,
                    mtime: p.mtime,
                    size: p.size,
                    title: &p.title,
                    artist: &p.artist,
                    album_artist: &p.album_artist,
                    album: p.album.as_deref(),
                    track_no: p.track_no,
                    disc_no: p.disc_no,
                    year: p.year,
                    duration_ms: p.duration_ms as i64,
                    track_gain: p.track_gain,
                    album_gain: p.album_gain,
                    cover_hash: p.cover_hash.as_deref(),
                    genre: p.genre.as_deref(),
                    composer: p.composer.as_deref(),
                    format: p.format.as_deref(),
                    sample_rate: p.sample_rate,
                    bit_depth: p.bit_depth,
                    bitrate: p.bitrate,
                    explicit: p.explicit,
                    art_hash: p.art_hash.as_deref(),
                    folder_art: p.folder_art.as_deref(),
                },
                now,
            )?;

            if done % 250 == 0 {
                on_event(ScanEvent::Parsed { done, total });
            }
            if done % 200 == 0 || batch_start.elapsed().as_millis() > 400 {
                txn.commit()?;
                txn = db.conn.unchecked_transaction()?;
                batch_start = Instant::now();
            }
        }

        // 3. Remove local tracks whose files are gone (remote tracks belong to their server's sync).
        stats.removed = crate::db::delete_tracks_where(&txn, |path| {
            !path.starts_with(crate::remote::PREFIX)
                && !seen_paths.contains(path)
                && !unreliable.iter().any(|r| path.starts_with(r.as_str()))
        })?;
        if stats.parsed > 0 || stats.removed > 0 {
            stats.covers_written = crate::db::pick_album_covers(&txn)?;
        }
        txn.commit()?;
        Ok(())
    })?;

    stats.elapsed_ms = t0.elapsed().as_millis();
    on_event(ScanEvent::Finished(stats.clone()));
    Ok(stats)
}

#[cfg(test)]
mod unavailable_tests {
    use super::*;

    pub(super) fn wav(path: &Path) {
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

    #[test]
    fn locked_disk_keeps_tracks() {
        let tmp = tempfile::tempdir().unwrap();
        let music = tmp.path().join("hd");
        std::fs::create_dir_all(music.join("Album")).unwrap();
        wav(&music.join("Album/a.wav"));
        wav(&music.join("Album/b.wav"));
        let mut db = Db::open(&tmp.path().join("db.sqlite")).unwrap();
        let covers = CoverCache::new(tmp.path().join("covers")).unwrap();
        let roots = vec![music.clone()];
        scan(&mut db, &covers, &roots, |_| {}).unwrap();
        assert_eq!(db.counts().unwrap().0, 2);

        // Disk locked: the mount point is empty, then gone entirely.
        std::fs::rename(&music, tmp.path().join("away")).unwrap();
        std::fs::create_dir_all(&music).unwrap();
        let s = scan(&mut db, &covers, &roots, |_| {}).unwrap();
        assert_eq!(s.removed, 0);
        std::fs::remove_dir(&music).unwrap();
        let s = scan(&mut db, &covers, &roots, |_| {}).unwrap();
        assert_eq!(s.removed, 0);
        assert_eq!(db.counts().unwrap().0, 2);
        assert!(!root_available(&music));

        // Back, minus one song: that one goes.
        std::fs::rename(tmp.path().join("away"), &music).unwrap();
        std::fs::remove_file(music.join("Album/b.wav")).unwrap();
        assert!(root_available(&music));
        let s = scan(&mut db, &covers, &roots, |_| {}).unwrap();
        assert_eq!(s.removed, 1);
    }
}

#[cfg(test)]
mod cover_vote_tests {
    use super::*;
    use lofty::config::WriteOptions;
    use lofty::picture::{MimeType, Picture, PictureType};
    use lofty::tag::{Tag, TagExt, TagType};

    fn png(rgb: [u8; 3]) -> Vec<u8> {
        let img = image::RgbImage::from_pixel(8, 8, image::Rgb(rgb));
        let mut out = std::io::Cursor::new(Vec::new());
        image::DynamicImage::ImageRgb8(img).write_to(&mut out, image::ImageFormat::Png).unwrap();
        out.into_inner()
    }

    fn song(path: &Path, album: &str, artist: &str, title: &str, pics: &[(PictureType, &[u8])]) {
        super::unavailable_tests::wav(path);
        let mut tag = Tag::new(TagType::Id3v2);
        tag.set_album(album.into());
        tag.set_artist(artist.into());
        tag.set_title(title.into());
        for (ty, data) in pics {
            tag.push_picture(Picture::new_unchecked(*ty, Some(MimeType::Png), None, data.to_vec()));
        }
        tag.save_to_path(path, WriteOptions::default()).unwrap();
    }

    fn album_cover(db: &Db, title: &str) -> Option<String> {
        db.conn.query_row("SELECT cover_hash FROM albums WHERE title=?1", [title], |r| r.get(0)).unwrap()
    }

    #[test]
    fn majority_beats_a_few_wrong_pictures() {
        let tmp = tempfile::tempdir().unwrap();
        let music = tmp.path().join("m");
        let right = png([200, 30, 30]);
        let wrong = png([30, 30, 200]);
        let back = png([30, 200, 30]);
        // The lossless copies (right art) and a few MP3-ish copies whose tag
        // carries another record's art, in their own folder with a stray
        // cover.jpg next to files of another album.
        std::fs::create_dir_all(music.join("CBJR/La Familia 013")).unwrap();
        std::fs::create_dir_all(music.join("Downloads")).unwrap();
        for i in 0..5 {
            song(&music.join(format!("CBJR/La Familia 013/{i}.wav")), "La Familia 013", "Charlie Brown Jr.", &format!("s{i}"),
                // a back cover listed first must not win over the front
                &[(PictureType::CoverBack, &back), (PictureType::CoverFront, &right)]);
        }
        for i in 0..2 {
            song(&music.join(format!("Downloads/{i}.wav")), "La Familia 013", "Charlie Brown Jr.", &format!("d{i}"),
                &[(PictureType::CoverFront, &wrong)]);
        }
        song(&music.join("Downloads/x.wav"), "Room on Fire", "The Strokes", "x", &[]);
        std::fs::write(music.join("Downloads/cover.png"), &wrong).unwrap();

        let mut db = Db::open(&tmp.path().join("db.sqlite")).unwrap();
        let covers = CoverCache::new(tmp.path().join("covers")).unwrap();
        scan(&mut db, &covers, &[music.clone()], |_| {}).unwrap();

        let right_h = blake3::hash(&right).to_hex()[..32].to_string();
        let wrong_h = blake3::hash(&wrong).to_hex()[..32].to_string();
        assert_eq!(album_cover(&db, "La Familia 013").as_deref(), Some(right_h.as_str()));
        // The other album has no art of its own: the shared folder's image is its only option.
        assert_eq!(album_cover(&db, "Room on Fire").as_deref(), Some(wrong_h.as_str()));

        // A cover the user picked by hand survives rescans.
        db.conn.execute("UPDATE albums SET cover_hash='mine', cover_user=1 WHERE title='La Familia 013'", []).unwrap();
        db.conn.execute("UPDATE tracks SET mtime=0", []).unwrap();
        scan(&mut db, &covers, &[music.clone()], |_| {}).unwrap();
        assert_eq!(album_cover(&db, "La Familia 013").as_deref(), Some("mine"));
    }

    #[test]
    fn album_folder_art_wins_a_tie() {
        let tmp = tempfile::tempdir().unwrap();
        let music = tmp.path().join("m");
        let folder = png([10, 10, 10]);
        let tagged = png([250, 250, 250]);
        std::fs::create_dir_all(music.join("A")).unwrap();
        song(&music.join("A/1.wav"), "Alb", "Art", "1", &[(PictureType::CoverFront, &tagged)]);
        song(&music.join("A/2.wav"), "Alb", "Art", "2", &[]);
        std::fs::write(music.join("A/folder.png"), &folder).unwrap();
        let mut db = Db::open(&tmp.path().join("db.sqlite")).unwrap();
        let covers = CoverCache::new(tmp.path().join("covers")).unwrap();
        scan(&mut db, &covers, &[music], |_| {}).unwrap();
        let h = blake3::hash(&folder).to_hex()[..32].to_string();
        assert_eq!(album_cover(&db, "Alb").as_deref(), Some(h.as_str()));
    }
}

#[cfg(test)]
mod filename_number_tests {
    use super::number_from_filename as n;

    #[test]
    fn reads_track_numbers_from_names() {
        assert_eq!(n("09 - Ninguém Entende Você"), Some((None, 9)));
        assert_eq!(n("11. Beco Sem Saída"), Some((None, 11)));
        assert_eq!(n("06_Uma Criança"), Some((None, 6)));
        assert_eq!(n("07 Song"), Some((None, 7)));
        assert_eq!(n("(03) Song"), Some((None, 3)));
        assert_eq!(n("1-09 Song"), Some((Some(1), 9)));
        assert_eq!(n("2.03 - Song"), Some((Some(2), 3)));
        assert_eq!(n("12"), Some((None, 12)));
    }

    #[test]
    fn leaves_titles_alone() {
        assert_eq!(n("99 Luftballons"), None);
        assert_eq!(n("1979 - Smashing"), None);
        assert_eq!(n("Song 09"), None);
        assert_eq!(n("00 - Intro"), None);
    }
}
