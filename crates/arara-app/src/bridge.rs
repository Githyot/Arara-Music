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
        /// "Buscando informações 120 de 1300" while artist/album info is fetched in the background.
        #[qproperty(QString, info_progress, cxx_name = "infoProgress")]
        /// JSON list of music folders that can't be read now (locked/unplugged disk).
        #[qproperty(QString, missing_dirs, cxx_name = "missingDirs")]
        type Library = super::LibraryRust;

        /// Opens the cached index (instant), starts a background rescan,
        /// folder watching, MPRIS and appearance tracking.
        #[qinvokable]
        fn open(self: Pin<&mut Library>);

        /// Scan, folder watching, MPRIS, appearance and server sync. Called once
        /// the window is on screen, so nothing here can keep it from showing.
        #[qinvokable]
        #[cxx_name = "startServices"]
        fn start_services(self: Pin<&mut Library>);

        /// The UI thread is alive (freeze reporter); `what` names the step it starts.
        #[qinvokable]
        fn heartbeat(self: &Library, what: &QString);

        #[qinvokable]
        #[cxx_name = "openMissingDir"]
        fn open_missing_dir(self: &Library, dir: &QString);

        #[qinvokable]
        #[cxx_name = "startScan"]
        fn start_scan(self: Pin<&mut Library>, dir: &QString);

        #[qinvokable]
        #[cxx_name = "albumsJson"]
        fn albums_json(self: &Library) -> QString;

        /// Forget a hand-picked cover and re-read this album's files, so its
        /// cover is chosen again from the embedded art and folder images.
        #[qinvokable]
        #[cxx_name = "refreshAlbumCover"]
        fn refresh_album_cover(self: Pin<&mut Library>, album_id: i64);

        /// Use an image file (path or file:// URL) as this album's cover.
        #[qinvokable]
        #[cxx_name = "setAlbumCover"]
        fn set_album_cover(self: Pin<&mut Library>, album_id: i64, image: &QString);

        /// Re-read every local file and choose every album cover again
        /// (hand-picked covers are kept).
        #[qinvokable]
        #[cxx_name = "rebuildCovers"]
        fn rebuild_covers(self: Pin<&mut Library>);

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

        /// Everything the home page ("Início") shows, in one call.
        #[qinvokable]
        #[cxx_name = "homeJson"]
        fn home_json(self: &Library, seed: i64) -> QString;

        /// Random songs for the home page's shuffle buttons: kind is "all" or "starred".
        #[qinvokable]
        #[cxx_name = "shuffleJson"]
        fn shuffle_json(self: &Library, kind: &QString, count: i32) -> QString;

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

        /// Listening history for the recap: a song started (returns the listen id)…
        #[qinvokable]
        #[cxx_name = "beginListen"]
        fn begin_listen(self: &Library, track_id: i64) -> i64;

        /// …and this much of it was actually heard since the last call.
        #[qinvokable]
        #[cxx_name = "addListenTime"]
        fn add_listen_time(self: &Library, listen_id: i64, ms: i64);

        /// Recap ("Retrospectiva") for [from, to) in unix seconds; to <= 0 means "until now".
        #[qinvokable]
        #[cxx_name = "recapJson"]
        fn recap_json(self: &Library, from: i64, to: i64) -> QString;

        /// Total time heard in [from, to), in ms.
        #[qinvokable]
        #[cxx_name = "listenedMs"]
        fn listened_ms(self: &Library, from: i64, to: i64) -> f64;

        /// Unix time of the first listen ever (0 when there is no history).
        #[qinvokable]
        #[cxx_name = "firstListen"]
        fn first_listen(self: &Library) -> f64;

        #[qinvokable]
        #[cxx_name = "clearListens"]
        fn clear_listens(self: &Library);

        /// Library tracks by id, in the order given (ids no longer there are skipped).
        #[qinvokable]
        #[cxx_name = "tracksByIdsJson"]
        fn tracks_by_ids_json(self: &Library, ids_json: &QString) -> QString;

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

        /// Transition analysis (silence, fades, loudness, tempo) on a worker
        /// thread, cached in the database; answers with `analysisReady`
        /// ("null" for remote tracks or undecodable files).
        #[qinvokable]
        #[cxx_name = "requestAnalysis"]
        fn request_analysis(self: Pin<&mut Library>, track_id: i64);

        /// Forget the stored lyrics (wrong version, unsynced) and look them up again.
        #[qinvokable]
        #[cxx_name = "refetchLyrics"]
        fn refetch_lyrics(self: Pin<&mut Library>, track_id: i64);

        /// Mirror player state to MPRIS. `track_json` is a track object or "null".
        #[qinvokable]
        #[cxx_name = "mprisUpdate"]
        fn mpris_update(self: &Library, status: &QString, track_json: &QString, can_next: bool, can_prev: bool, volume: f64);

        /// Playback speed changed in the app (1.0 = normal).
        #[qinvokable]
        #[cxx_name = "mprisRate"]
        fn mpris_rate(self: &Library, rate: f64);

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

        /// Everything about one song for its info page: library data (plays,
        /// dates, numbers) plus what the file's tags say (credits, label, audio).
        #[qinvokable]
        #[cxx_name = "trackInfoJson"]
        fn track_info_json(self: &Library, track_id: i64) -> QString;

        /// Album summary from the library: length, genres, plays, quality, tags.
        #[qinvokable]
        #[cxx_name = "albumInfoJson"]
        fn album_info_json(self: &Library, album_id: i64) -> QString;

        /// Artist summary from the library: counts, years, genres, top songs.
        #[qinvokable]
        #[cxx_name = "artistInfoJson"]
        fn artist_info_json(self: &Library, artist_id: i64) -> QString;

        /// Look the item up on MusicBrainz/Wikipedia (cached); answers with
        /// `onlineInfo`. kind: "track" | "album" | "artist".
        #[qinvokable]
        #[cxx_name = "requestOnlineInfo"]
        fn request_online_info(self: Pin<&mut Library>, kind: &QString, id: i64, force: bool);

        /// `json` is null when nothing was found or the lookup is off.
        #[qsignal]
        #[cxx_name = "onlineInfo"]
        fn online_info(self: Pin<&mut Library>, kind: QString, id: i64, json: QString);

        /// Animated cover of an album, if it is already on disk ("" otherwise).
        /// When the preference is on and the album wasn't asked yet, it is
        /// looked up and downloaded in the background; `motionCoverReady` follows.
        #[qinvokable]
        #[cxx_name = "motionCover"]
        fn motion_cover(self: Pin<&mut Library>, album_id: i64) -> QString;

        #[qsignal]
        #[cxx_name = "motionCoverReady"]
        fn motion_cover_ready(self: Pin<&mut Library>, album_id: i64, url: QString);

        /// Queue every album of the library for an animated cover (Preferences).
        #[qinvokable]
        #[cxx_name = "downloadAllMotionCovers"]
        fn download_all_motion_covers(self: Pin<&mut Library>);

        /// Background queue progress: albums checked / queued, animated covers found.
        #[qsignal]
        #[cxx_name = "motionProgress"]
        fn motion_progress(self: Pin<&mut Library>, done: i32, total: i32, found: i32);

        /// Delete the downloaded animated covers; returns how many files went.
        #[qinvokable]
        #[cxx_name = "clearMotionCovers"]
        fn clear_motion_covers(self: Pin<&mut Library>) -> i32;

        /// {"files": n, "bytes": n} of the animated cover cache.
        #[qinvokable]
        #[cxx_name = "motionCacheJson"]
        fn motion_cache_json(self: &Library) -> QString;

        /// Library items sharing a genre/tag ("Similares" page): artists,
        /// albums and songs, local and from synced servers. `exclude_artist`
        /// (-1 = none) is the artist whose chip was clicked.
        #[qinvokable]
        #[cxx_name = "tagJson"]
        fn tag_json(self: &Library, tag: &QString, exclude_artist: i64) -> QString;

        /// Artists with this tag on MusicBrainz (cached); answers with `tagOnline`.
        /// `area` ("Brazil") puts artists from there first.
        #[qinvokable]
        #[cxx_name = "requestTagOnline"]
        fn request_tag_online(self: Pin<&mut Library>, tag: &QString, area: &QString);

        /// `json` is null when the lookup is off or failed.
        #[qsignal]
        #[cxx_name = "tagOnline"]
        fn tag_online(self: Pin<&mut Library>, tag: QString, json: QString);

        /// Open the folder holding a local track in the file manager, with the file selected when possible.
        #[qinvokable]
        #[cxx_name = "showInFolder"]
        fn show_in_folder(self: &Library, track_id: i64) -> bool;

        /// Plain text of the stored lyrics ("" when none), for sharing.
        #[qinvokable]
        #[cxx_name = "lyricsText"]
        fn lyrics_text(self: &Library, track_id: i64) -> QString;
        /// What the "Editar informações" dialog shows for one song (library data only).
        #[qinvokable]
        #[cxx_name = "editableJson"]
        fn editable_json(self: &Library, track_id: i64) -> QString;

        /// Save edited details (JSON with title, artist, albumArtist, album,
        /// trackNo, discNo, year, genre, composer). `cover` is an image file
        /// ("" keeps the picture). With `write_file`, local files get the tags
        /// written into them. Runs in the background; answers with trackEdited.
        #[qinvokable]
        #[cxx_name = "saveTrackEdit"]
        fn save_track_edit(self: Pin<&mut Library>, track_id: i64, json: &QString, cover: &QString, write_file: bool);

        /// Drop changes kept only in the library; the song is read again from its file or server.
        #[qinvokable]
        #[cxx_name = "revertTrackEdit"]
        fn revert_track_edit(self: Pin<&mut Library>, track_id: i64) -> bool;

        /// `json`: {trackId, wroteFile, warning, error, track} (track = the song as the lists show it).
        #[qsignal]
        #[cxx_name = "trackEdited"]
        fn track_edited(self: Pin<&mut Library>, track_id: i64, json: QString);

        #[qsignal]
        #[cxx_name = "analysisReady"]
        fn analysis_ready(self: Pin<&mut Library>, track_id: i64, json: QString);

        /// play, pause, playpause, stop, next, previous, seek (arg = µs offset),
        /// setposition (arg = µs), raise, quit
        #[qsignal]
        #[cxx_name = "mediaCommand"]
        fn media_command(self: Pin<&mut Library>, command: QString, arg: i64);
    }

    impl cxx_qt::Threading for Library {}
}

use crate::desktop::{self, Command, Mpris, TrackMeta};
use arara_core::{covers::CoverCache, db::Db, import, lyrics, remote, scanner, watcher::LibraryWatcher, Paths};
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
    info_progress: QString,
    missing_dirs: QString,
    prefetching: std::sync::Arc<std::sync::atomic::AtomicBool>,
    info_running: std::sync::Arc<std::sync::atomic::AtomicBool>,
    resolver: remote::Resolver,
    sync_queue: Vec<i64>,
    db_path: PathBuf,
    covers_dir: PathBuf,
    db: Option<Db>,
    rescan_pending: bool,
    watch_gen: std::sync::Arc<std::sync::atomic::AtomicU64>,
    mpris: Option<Mpris>,
    inhibit: Option<desktop::Inhibitor>,
    motion: Option<MotionQueue>,
}

/// One worker thread that looks up and downloads animated covers, one album
/// at a time (gentle on the lookup service and on the disk).
struct MotionQueue {
    tx: std::sync::mpsc::Sender<(i64, String, String)>,
    /// Albums queued or being fetched, so a page opened twice asks once.
    pending: std::sync::Arc<std::sync::Mutex<std::collections::HashSet<i64>>>,
    total: std::sync::Arc<std::sync::atomic::AtomicI32>,
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
            info_progress: QString::default(),
            prefetching: Default::default(),
            info_running: Default::default(),
            resolver: remote::Resolver::default(),
            sync_queue: Vec::new(),
            db_path: p.db,
            covers_dir: p.covers,
            db: None,
            rescan_pending: false,
            watch_gen: Default::default(),
            missing_dirs: QString::from("[]"),
            mpris: None,
            inhibit: None,
            motion: None,
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

fn rusqlite_params<'a>(id: i64, name: &'a str, like: &'a str) -> (i64, &'a str, &'a str) {
    (id, name, like)
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
        crate::watchdog::step("abrindo o banco de dados");
        let db = Db::open(&self.db_path).ok();
        let stored_dir = db.as_ref().and_then(|d| d.get_kv("library_dir").ok().flatten());
        self.as_mut().rust_mut().resolver = db.as_ref().map(remote::Resolver::load).unwrap_or_default();
        self.as_mut().rust_mut().db = db;
        self.as_mut().refresh_counts();
        let dir = stored_dir.unwrap_or_else(default_music_dir);
        self.as_mut().set_library_dir(qs(&dir));
        crate::watchdog::step("lendo a biblioteca salva");
        self.as_mut().library_changed();
        self.as_mut().playlists_changed();
        self.as_mut().servers_changed();
    }

    pub fn start_services(mut self: Pin<&mut Self>) {
        let dir = self.library_dir.clone();
        crate::watchdog::step("procurando músicas novas");
        self.as_mut().start_scan(&dir);
        crate::watchdog::step("vigiando as pastas de música");
        let d = dir.to_string();
        self.as_mut().start_watching(&d);
        crate::watchdog::step("integração com o GNOME (MPRIS, tema)");
        self.as_mut().start_desktop_integration();
        // Remote catalogs are already cached; refresh them in the background
        // (the writer lock makes this wait for the local scan).
        crate::watchdog::step("sincronizando servidores");
        self.as_mut().sync_servers(-1);
        crate::watchdog::step("pronto");
    }

    pub fn heartbeat(&self, what: &QString) {
        if what.is_empty() {
            crate::watchdog::beat();
        } else {
            crate::watchdog::step(&what.to_string());
        }
    }

    fn start_watching(mut self: Pin<&mut Self>, _dir: &str) {
        let dirs = self.library_dirs();
        self.as_mut().watch_dirs(&dirs);
    }

    /// Watches the music folders from a helper thread. Nothing here touches the
    /// disk on the UI thread: an external drive that is spinning up, locked or
    /// half-mounted can block any file access for a long time. The thread also
    /// notices when a folder goes away or comes back (disk unlocked in Files)
    /// and rescans then.
    fn watch_dirs(self: Pin<&mut Self>, dirs: &[String]) {
        use std::sync::atomic::Ordering;
        let qt = self.qt_thread();
        let roots: Vec<PathBuf> = dirs.iter().map(PathBuf::from).collect();
        let gen_ref = self.watch_gen.clone();
        let gen = gen_ref.fetch_add(1, Ordering::SeqCst) + 1;
        let db_path = self.db_path.clone();
        let _ = std::thread::Builder::new().name("arara-folders".into()).spawn(move || {
            // Folders that have songs in the index: if one of them is empty now,
            // it's an unmounted disk, not a new empty folder.
            let known: Vec<bool> = {
                let db = Db::open(&db_path).ok();
                roots
                    .iter()
                    .map(|r| {
                        let mut prefix = r.to_string_lossy().into_owned();
                        if !prefix.ends_with(std::path::MAIN_SEPARATOR) {
                            prefix.push(std::path::MAIN_SEPARATOR);
                        }
                        db.as_ref()
                            .and_then(|d| {
                                d.conn
                                    .query_row(
                                        "SELECT 1 FROM tracks WHERE substr(path, 1, length(?1)) = ?1 LIMIT 1",
                                        [&prefix],
                                        |_| Ok(()),
                                    )
                                    .ok()
                            })
                            .is_some()
                    })
                    .collect()
            };
            let mut prev: Option<Vec<bool>> = None;
            let mut watcher: Option<LibraryWatcher> = None;
            while gen_ref.load(Ordering::SeqCst) == gen {
                let now: Vec<bool> = roots
                    .iter()
                    .zip(&known)
                    .map(|(r, k)| scanner::root_available(r) || (!k && r.is_dir()))
                    .collect();
                if prev.as_ref() != Some(&now) {
                    let came_back = prev.as_ref().map(|p| p.iter().zip(&now).any(|(a, b)| !a && *b)).unwrap_or(false);
                    let ok: Vec<PathBuf> = roots.iter().zip(&now).filter(|(_, a)| **a).map(|(r, _)| r.clone()).collect();
                    let missing: Vec<String> =
                        roots.iter().zip(&now).filter(|(_, a)| !**a).map(|(r, _)| r.to_string_lossy().into_owned()).collect();
                    watcher = None;
                    let q = qt.clone();
                    match LibraryWatcher::new(&ok, std::time::Duration::from_secs(2), move || {
                        let _ = q.queue(|o| o.rescan());
                    }) {
                        Ok(w) => watcher = Some(w),
                        Err(e) => log::warn!("folder watching unavailable: {e}"),
                    }
                    let json = serde_json::to_string(&missing).unwrap();
                    let _ = qt.queue(move |mut o| {
                        o.as_mut().set_missing_dirs(qs(&json));
                        if came_back {
                            o.as_mut().rescan();
                        }
                    });
                    prev = Some(now);
                }
                for _ in 0..16 {
                    std::thread::sleep(std::time::Duration::from_millis(250));
                    if gen_ref.load(Ordering::SeqCst) != gen {
                        break;
                    }
                }
            }
            drop(watcher);
        });
    }

    /// Opens the file manager where the missing folder should be, so the user
    /// can unlock or mount the disk there (GNOME asks for the password).
    pub fn open_missing_dir(&self, dir: &QString) {
        let dir = PathBuf::from(dir.to_string());
        std::thread::spawn(move || {
            let mut p = dir.as_path();
            while !p.is_dir() {
                match p.parent() {
                    Some(q) => p = q,
                    None => break,
                }
            }
            let target = p.to_path_buf();
            #[cfg(not(windows))]
            let _ = std::process::Command::new("gio").arg("open").arg(&target).spawn().or_else(|_| {
                std::process::Command::new("xdg-open").arg(&target).spawn()
            });
            #[cfg(windows)]
            let _ = std::process::Command::new("explorer").arg(&target).spawn();
        });
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
                Command::SetRate(milli) => ("setrate", milli),
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
                        o.as_mut().prefetch_info();
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

    /// Runs `work` on a fresh connection off the UI thread (it may wait on the
    /// scanner's write lock), then `after` back on the UI thread.
    fn db_job(
        &self,
        work: impl FnOnce(&Db) -> arara_core::Result<()> + Send + 'static,
        after: impl FnOnce(Pin<&mut qobject::Library>) + Send + 'static,
    ) {
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        std::thread::spawn(move || {
            let ok = Db::open(&db_path).and_then(|db| work(&db));
            match ok {
                Ok(()) => {
                    let _ = qt.queue(after);
                }
                Err(e) => log::warn!("cover job failed: {e}"),
            }
        });
    }

    pub fn refresh_album_cover(self: Pin<&mut Self>, album_id: i64) {
        self.db_job(
            move |db| {
                db.reread_album_cover(album_id)
            },
            |o| o.rescan(),
        );
    }

    pub fn set_album_cover(self: Pin<&mut Self>, album_id: i64, image: &QString) {
        let path = remote::url_to_path(&image.to_string());
        let covers_dir = self.covers_dir.clone();
        self.db_job(
            move |db| {
                let bytes = std::fs::read(&path)?;
                let hash = CoverCache::new(&covers_dir)?.store(&bytes)?;
                db.set_user_cover(album_id, &hash)
            },
            |o| o.library_changed(),
        );
    }

    pub fn rebuild_covers(self: Pin<&mut Self>) {
        self.db_job(
            |db| {
                db.reread_all_covers()
            },
            |o| o.rescan(),
        );
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

    pub fn home_json(&self, seed: i64) -> QString {
        let Some(db) = &self.db else { return qs("{}") };
        let albums = |r: arara_core::Result<Vec<arara_core::db::AlbumRow>>| -> Vec<serde_json::Value> {
            r.unwrap_or_default().iter().map(|a| self.album_value(a)).collect()
        };
        let tracks = |r: arara_core::Result<Vec<arara_core::db::TrackRow>>| -> Vec<serde_json::Value> {
            r.unwrap_or_default().iter().map(|t| self.track_value(t)).collect()
        };
        let artists: Vec<_> = db
            .top_artists(12)
            .unwrap_or_default()
            .iter()
            .map(|a| json!({ "id": a.id, "name": a.name, "albums": a.album_count, "cover": self.cover(&a.cover_hash, 256) }))
            .collect();
        let starred = db.random_starred(1).map(|v| !v.is_empty()).unwrap_or(false);
        let v = json!({
            "recentAlbums": albums(db.recent_albums(12)),
            "addedAlbums": albums(db.added_albums(12)),
            "rediscover": albums(db.rediscover_albums(30, now(), seed, 12)),
            "topArtists": artists,
            "topTracks": tracks(db.most_played(10)),
            "recentTracks": tracks(db.recent_tracks(10)),
            "hasStarred": starred,
        });
        qs(&v.to_string())
    }

    pub fn shuffle_json(&self, kind: &QString, count: i32) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let n = count.clamp(1, 2000) as i64;
        if kind.to_string() == "starred" {
            self.tracks_to_json(db.random_starred(n))
        } else {
            self.tracks_to_json(db.random_tracks(n))
        }
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

    pub fn begin_listen(&self, track_id: i64) -> i64 {
        self.db.as_ref().and_then(|db| db.begin_listen(track_id, now()).ok()).unwrap_or(0)
    }

    pub fn add_listen_time(&self, listen_id: i64, ms: i64) {
        if let Some(db) = &self.db {
            let _ = db.add_listen_ms(listen_id, ms);
        }
    }

    pub fn recap_json(&self, from: i64, to: i64) -> QString {
        let Some(db) = &self.db else { return qs("{}") };
        let to = if to <= 0 { i64::MAX } else { to };
        let Ok(r) = db.recap(from, to, 10) else { return qs("{}") };
        let ranked = |v: &[arara_core::stats::Ranked]| -> Vec<serde_json::Value> {
            v.iter()
                .map(|x| json!({
                    "name": x.name, "artist": x.artist, "ms": x.ms, "plays": x.plays, "id": x.id,
                    "cover": self.cover(&x.cover_hash, 256), "coverBig": self.cover(&x.cover_hash, 640),
                }))
                .collect()
        };
        let v = json!({
            "totalMs": r.total_ms, "plays": r.plays, "tracks": r.tracks, "artists": r.artists,
            "albums": r.albums, "daysActive": r.days_active, "streak": r.longest_streak,
            "topArtists": ranked(&r.top_artists), "topTracks": ranked(&r.top_tracks),
            "topAlbums": ranked(&r.top_albums), "topGenres": ranked(&r.top_genres),
            "newArtists": ranked(&r.new_artists),
            "hours": r.hours, "weekdays": r.weekdays,
            "days": r.days.iter().map(|(d, ms)| json!({ "d": d, "ms": ms })).collect::<Vec<_>>(),
            "firstListen": r.first_listen,
        });
        qs(&v.to_string())
    }

    pub fn listened_ms(&self, from: i64, to: i64) -> f64 {
        let to = if to <= 0 { i64::MAX } else { to };
        self.db.as_ref().and_then(|db| db.listened_ms(from, to).ok()).unwrap_or(0) as f64
    }

    pub fn first_listen(&self) -> f64 {
        self.db.as_ref().and_then(|db| db.first_listen().ok().flatten()).unwrap_or(0) as f64
    }

    pub fn tracks_by_ids_json(&self, ids_json: &QString) -> QString {
        let Some(db) = &self.db else { return qs("[]") };
        let ids: Vec<i64> = serde_json::from_str(&ids_json.to_string()).unwrap_or_default();
        self.tracks_to_json(db.tracks_by_ids(&ids))
    }

    pub fn clear_listens(&self) {
        if let Some(db) = &self.db {
            let _ = db.clear_listens();
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

    // ---------- info pages ----------

    fn file_url_of(path: &str) -> String {
        remote::file_url(path)
    }

    pub fn track_info_json(&self, track_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("null") };
        let Ok(Some(t)) = db.track(track_id) else { return qs("null") };
        let mut v = self.track_value(&t);
        let extra = db.conn.query_row(
            "SELECT track_no, disc_no, play_count, last_played, added_at, composer, size FROM tracks WHERE id = ?1",
            [track_id],
            |r| Ok(json!({
                "trackNo": r.get::<_, Option<i64>>(0)?, "discNo": r.get::<_, Option<i64>>(1)?,
                "plays": r.get::<_, i64>(2)?, "lastPlayed": r.get::<_, Option<i64>>(3)?,
                "addedAt": r.get::<_, Option<i64>>(4)?, "composer": r.get::<_, Option<String>>(5)?,
                "size": r.get::<_, i64>(6)?,
            })),
        ).unwrap_or(json!({}));
        if let (Some(o), Some(e)) = (v.as_object_mut(), extra.as_object()) {
            for (k, x) in e {
                o.insert(k.clone(), x.clone());
            }
        }
        let local = !remote::is_remote(&t.path);
        v["albumArtist"] = json!(t.album_artist);
        v["local"] = json!(local);
        v["path"] = json!(if local { t.path.clone() } else { String::new() });
        v["folderUrl"] = json!(if local {
            std::path::Path::new(&t.path).parent().map(|p| Self::file_url_of(&p.to_string_lossy())).unwrap_or_default()
        } else {
            String::new()
        });
        v["edited"] = json!(arara_core::edit::override_for(&db.conn, &t.path).ok().flatten().is_some());
        v["hasLyrics"] = json!(db.cached_lyrics(track_id).ok().flatten().map(|(src, a, b)| src != "none" && (a.is_some() || b.is_some())).unwrap_or(false));
        v["file"] = if local { arara_core::info::file_details(&t.path) } else { json!({}) };
        qs(&v.to_string())
    }

    pub fn album_info_json(&self, album_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("null") };
        let tracks = db.album_tracks(album_id).unwrap_or_default();
        let stats = db.conn.query_row(
            "SELECT COUNT(*), COALESCE(SUM(duration_ms),0), COALESCE(SUM(play_count),0), MIN(added_at), MAX(last_played),
                    COUNT(DISTINCT COALESCE(disc_no,1)), GROUP_CONCAT(DISTINCT composer)
             FROM tracks WHERE album_id = ?1",
            [album_id],
            |r| Ok(json!({
                "tracks": r.get::<_, i64>(0)?, "durationMs": r.get::<_, i64>(1)?, "plays": r.get::<_, i64>(2)?,
                "addedAt": r.get::<_, Option<i64>>(3)?, "lastPlayed": r.get::<_, Option<i64>>(4)?,
                "discs": r.get::<_, i64>(5)?, "composers": r.get::<_, Option<String>>(6)?,
            })),
        ).unwrap_or(json!({}));
        let mut genres: Vec<String> = vec![];
        for t in &tracks {
            if let Some(g) = &t.genre {
                if !genres.contains(g) {
                    genres.push(g.clone());
                }
            }
        }
        let mut grades: Vec<String> = vec![];
        for t in &tracks {
            let d = t.quality().1;
            if !d.is_empty() && !grades.contains(&d) {
                grades.push(d);
            }
        }
        let best = tracks.iter().map(|t| t.quality().0).find(|g| *g == "Hi-Res").or_else(|| tracks.iter().map(|t| t.quality().0).find(|g| !g.is_empty())).unwrap_or("");
        // Label, copyright and release date usually live in every track's tags: read the first local one.
        let file = tracks.iter().find(|t| !remote::is_remote(&t.path)).map(|t| arara_core::info::file_details(&t.path)).unwrap_or(json!({}));
        let composers: Vec<String> = stats["composers"].as_str().unwrap_or("").split(',').map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()).take(8).collect();
        let first = tracks.first();
        let folder = first.filter(|t| !remote::is_remote(&t.path)).and_then(|t| std::path::Path::new(&t.path).parent().map(|p| p.to_string_lossy().into_owned())).unwrap_or_default();
        let v = json!({
            "stats": stats, "genres": genres, "qualities": grades, "grade": best, "composers": composers,
            "fields": file["fields"], "mbid": file["mbid"], "folder": folder,
            "folderUrl": if folder.is_empty() { String::new() } else { Self::file_url_of(&folder) },
            "year": first.and_then(|t| t.year),
        });
        qs(&v.to_string())
    }

    pub fn artist_info_json(&self, artist_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("null") };
        let name: String = db.conn.query_row("SELECT name FROM artists WHERE id = ?1", [artist_id], |r| r.get(0)).unwrap_or_default();
        // Songs credited to the artist: on their albums, or as track artist ("feat." included).
        let like = format!("%{}%", name.replace('%', "").replace('_', ""));
        let cond = "(a.artist_id = ?1 OR t.artist = ?2 COLLATE NOCASE OR t.artist LIKE ?3)";
        let stats = db.conn.query_row(
            &format!("SELECT COUNT(*), COALESCE(SUM(t.duration_ms),0), COALESCE(SUM(t.play_count),0), MIN(COALESCE(t.year,a.year)), MAX(COALESCE(t.year,a.year)),
                    MAX(t.last_played), SUM(t.starred)
             FROM tracks t LEFT JOIN albums a ON a.id = t.album_id WHERE {cond}"),
            rusqlite_params(artist_id, &name, &like),
            |r| Ok(json!({
                "tracks": r.get::<_, i64>(0)?, "durationMs": r.get::<_, i64>(1)?, "plays": r.get::<_, i64>(2)?,
                "firstYear": r.get::<_, Option<i64>>(3)?, "lastYear": r.get::<_, Option<i64>>(4)?,
                "lastPlayed": r.get::<_, Option<i64>>(5)?, "starred": r.get::<_, Option<i64>>(6)?.unwrap_or(0),
            })),
        ).unwrap_or(json!({}));
        let mut genres: Vec<(String, i64)> = vec![];
        if let Ok(mut st) = db.conn.prepare(&format!(
            "SELECT t.genre, COUNT(*) c FROM tracks t LEFT JOIN albums a ON a.id = t.album_id WHERE {cond} AND t.genre IS NOT NULL GROUP BY t.genre COLLATE NOCASE ORDER BY c DESC LIMIT 5"
        )) {
            if let Ok(rows) = st.query_map(rusqlite_params(artist_id, &name, &like), |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?))) {
                genres = rows.flatten().collect();
            }
        }
        let mut top_ids: Vec<i64> = vec![];
        if let Ok(mut st) = db.conn.prepare(&format!(
            "SELECT t.id FROM tracks t LEFT JOIN albums a ON a.id = t.album_id WHERE {cond}
             ORDER BY t.play_count DESC, t.starred DESC, t.last_played DESC, COALESCE(t.year,a.year) DESC LIMIT 5"
        )) {
            if let Ok(rows) = st.query_map(rusqlite_params(artist_id, &name, &like), |r| r.get::<_, i64>(0)) {
                top_ids = rows.flatten().collect();
            }
        }
        let mut top = db.tracks_by_ids(&top_ids).unwrap_or_default();
        top.sort_by_key(|t| top_ids.iter().position(|i| *i == t.id));
        // Albums by other artists where this one shows up on some track.
        let mut appears: Vec<serde_json::Value> = vec![];
        if let Ok(mut st) = db.conn.prepare(
            "SELECT DISTINCT a.id FROM tracks t JOIN albums a ON a.id = t.album_id
             WHERE (a.artist_id IS NULL OR a.artist_id != ?1) AND (t.artist = ?2 COLLATE NOCASE OR t.artist LIKE ?3) LIMIT 12",
        ) {
            let ids: Vec<i64> = st.query_map(rusqlite_params(artist_id, &name, &like), |r| r.get(0)).map(|r| r.flatten().collect()).unwrap_or_default();
            let all = db.albums().unwrap_or_default();
            appears = all.iter().filter(|a| ids.contains(&a.id)).map(|a| self.album_value(a)).collect();
        }
        // Artist MBID from the tags of one of their files, when tagged by Picard.
        let mbid = top.iter().find(|t| !remote::is_remote(&t.path)).and_then(|t| arara_core::info::file_details(&t.path)["mbid"]["artist"].as_str().map(str::to_owned));
        let v = json!({
            "name": name, "stats": stats,
            "genres": genres.iter().map(|g| g.0.clone()).collect::<Vec<_>>(),
            "top": top.iter().map(|t| self.track_value(t)).collect::<Vec<_>>(),
            "appearsOn": appears, "mbid": mbid,
        });
        qs(&v.to_string())
    }

    fn online_allowed(&self) -> bool {
        std::env::var("ARARA_OFFLINE").is_err()
            && self.db.as_ref().and_then(|d| d.get_kv("pref:onlineinfo").ok().flatten()).map_or(true, |v| v != "0")
    }

    /// Where info files may go and what may be touched, for worker threads.
    fn info_options(&self) -> arara_core::infostore::Options {
        let pref = |k: &str| self.db.as_ref().and_then(|d| d.get_kv(k).ok().flatten());
        arara_core::infostore::Options {
            save_files: pref("pref:infofiles").map_or(true, |v| v != "0"),
            roots: self.library_dirs(),
            skip: serde_json::from_str(&self.missing_dirs.to_string()).unwrap_or_default(),
            photo_cache: self.covers_dir.join("web"),
            online: self.online_allowed(),
        }
    }

    pub fn request_online_info(self: Pin<&mut Self>, kind: &QString, id: i64, force: bool) {
        let kind = kind.to_string();
        let qt = self.qt_thread();
        if !self.online_allowed() || self.db.is_none() {
            let _ = qt.queue(move |o| o.online_info(qs(&kind), id, qs("null")));
            return;
        }
        let opts = self.info_options();
        let db_path = self.db_path.clone();
        // Everything, even reading tags for MusicBrainz ids, happens on the
        // worker: the files may sit on a disk that is slow to answer.
        std::thread::spawn(move || {
            use arara_core::{info, infostore};
            let Ok(db) = Db::open(&db_path) else { return };
            let send = |v: &serde_json::Value| {
                let s = v.to_string();
                let k = kind.clone();
                let _ = qt.queue(move |o| o.online_info(qs(&k), id, qs(&s)));
            };
            match kind.as_str() {
                "album" => {
                    let mut d = send;
                    infostore::album(&db, id, now(), force, &opts, &mut d);
                }
                "artist" => {
                    let mut d = send;
                    infostore::artist(&db, id, now(), force, &opts, &mut d);
                }
                "track" => {
                    let Some(t) = db.track(id).ok().flatten() else { return send(&serde_json::Value::Null) };
                    let mbid = (!remote::is_remote(&t.path) && !opts.skip.iter().any(|s| t.path.starts_with(s.as_str())))
                        .then(|| info::file_details(&t.path)["mbid"]["recording"].as_str().map(str::to_owned))
                        .flatten();
                    let key = format!("{}\u{1f}{}\u{1f}{}", t.artist, t.title, t.album.clone().unwrap_or_default());
                    let data = info::cached_or_fetch(&db, "track", &key, now(), force, || {
                        info::fetch_recording(&t.title, &t.artist, t.album.as_deref(), t.duration_ms, mbid.as_deref())
                    });
                    send(&data);
                }
                _ => send(&serde_json::Value::Null),
            }
        });
    }

    /// After indexing: look up info for every album and artist with local
    /// files, most played first, and save it next to the music. One run at a
    /// time; items already done are skipped, so it resumes where it stopped.
    pub fn prefetch_info(self: Pin<&mut Self>) {
        use std::sync::atomic::Ordering;
        if !self.online_allowed() || self.db.is_none() {
            return;
        }
        if self.db.as_ref().and_then(|d| d.get_kv("pref:infoprefetch").ok().flatten()).as_deref() == Some("0") {
            return;
        }
        let running = self.info_running.clone();
        if running.swap(true, Ordering::SeqCst) {
            return;
        }
        let opts = self.info_options();
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        let _ = std::thread::Builder::new().name("arara-info".into()).spawn(move || {
            use arara_core::infostore::{self, Outcome};
            let run = || {
                let Ok(db) = Db::open(&db_path) else { return };
                let list = infostore::prefetch_list(&db);
                let total = list.len();
                let (mut done, mut fetched, mut offline_streak) = (0usize, 0usize, 0u32);
                let mut last_msg = std::time::Instant::now() - std::time::Duration::from_secs(10);
                for (kind, id) in list {
                    let mut nothing = |_: &serde_json::Value| {};
                    let (_, outcome) = if kind == "album" {
                        infostore::album(&db, id, now(), false, &opts, &mut nothing)
                    } else {
                        infostore::artist(&db, id, now(), false, &opts, &mut nothing)
                    };
                    done += 1;
                    match outcome {
                        Outcome::Fetched => {
                            fetched += 1;
                            offline_streak = 0;
                        }
                        Outcome::Offline => offline_streak += 1,
                        Outcome::Missing => offline_streak = 0,
                        _ => {}
                    }
                    if offline_streak >= 8 {
                        log::info!("info prefetch stopped: offline ({done} of {total})");
                        break;
                    }
                    if matches!(outcome, Outcome::Fetched | Outcome::Missing | Outcome::Offline) || last_msg.elapsed().as_millis() > 500 {
                        last_msg = std::time::Instant::now();
                        let msg = format!("Buscando informações {done} de {total}");
                        let _ = qt.queue(move |o| o.set_info_progress(qs(&msg)));
                    }
                }
                log::info!("info prefetch: {fetched} looked up online, {done} of {total} checked");
            };
            run();
            running.store(false, Ordering::SeqCst);
            let _ = qt.queue(|o| o.set_info_progress(QString::default()));
        });
    }

    fn motion_dir(&self) -> PathBuf {
        self.covers_dir.join("motion")
    }

    fn motion_enabled(&self) -> bool {
        self.online_allowed() && self.db.as_ref().and_then(|d| d.get_kv("pref:motioncovers").ok().flatten()).is_some_and(|v| v == "1")
    }

    /// (artist, title) of an album, from the index only.
    fn album_names(&self, album_id: i64) -> Option<(String, String)> {
        let db = self.db.as_ref()?;
        db.conn.query_row(
            "SELECT COALESCE(ar.name, ''), al.title FROM albums al LEFT JOIN artists ar ON ar.id = al.artist_id WHERE al.id = ?1",
            [album_id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
        ).ok()
    }

    fn motion_queue(mut self: Pin<&mut Self>) -> &MotionQueue {
        if self.motion.is_none() {
            let (tx, rx) = std::sync::mpsc::channel::<(i64, String, String)>();
            let pending: std::sync::Arc<std::sync::Mutex<std::collections::HashSet<i64>>> = Default::default();
            let total: std::sync::Arc<std::sync::atomic::AtomicI32> = Default::default();
            let qt = self.qt_thread();
            let db_path = self.db_path.clone();
            let dir = self.motion_dir();
            let (p2, t2) = (pending.clone(), total.clone());
            std::thread::Builder::new().name("motion-covers".into()).spawn(move || {
                use std::sync::atomic::Ordering;
                let Ok(db) = Db::open(&db_path) else { return };
                let (mut done, mut found) = (0i32, 0i32);
                for (id, artist, title) in rx {
                    let url = match arara_core::motion::cached(&db, &dir, &artist, &title, now()) {
                        arara_core::motion::Cached::Ready(p) => Some(p),
                        arara_core::motion::Cached::Missing => None,
                        arara_core::motion::Cached::Unknown => {
                            let r = arara_core::motion::fetch(&db, &dir, &artist, &title, now(), arara_core::motion::DEFAULT_SIDE);
                            // Be gentle with the free lookup service.
                            std::thread::sleep(std::time::Duration::from_millis(700));
                            r
                        }
                    };
                    let url = url.map(|p| remote::file_url(&p.to_string_lossy())).unwrap_or_default();
                    p2.lock().unwrap().remove(&id);
                    done += 1;
                    if !url.is_empty() { found += 1; }
                    let total = t2.load(Ordering::Relaxed);
                    let idle = p2.lock().unwrap().is_empty();
                    let (d, f) = (done, found);
                    if idle { done = 0; found = 0; t2.store(0, Ordering::Relaxed); }
                    let _ = qt.queue(move |mut o| {
                        o.as_mut().motion_cover_ready(id, qs(&url));
                        o.motion_progress(d, total, f);
                    });
                }
            }).ok();
            self.as_mut().rust_mut().motion = Some(MotionQueue { tx, pending, total });
        }
        self.into_ref().get_ref().motion.as_ref().unwrap()
    }

    fn enqueue_motion(self: Pin<&mut Self>, album_id: i64, artist: String, title: String) {
        let q = self.motion_queue();
        if q.pending.lock().unwrap().insert(album_id) {
            q.total.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let _ = q.tx.send((album_id, artist, title));
        }
    }

    pub fn motion_cover(self: Pin<&mut Self>, album_id: i64) -> QString {
        if !self.motion_enabled() {
            return QString::default();
        }
        let Some((artist, title)) = self.album_names(album_id) else { return QString::default() };
        if title.trim().is_empty() {
            return QString::default();
        }
        let Some(db) = self.db.as_ref() else { return QString::default() };
        match arara_core::motion::cached(db, &self.motion_dir(), &artist, &title, now()) {
            arara_core::motion::Cached::Ready(p) => qs(&remote::file_url(&p.to_string_lossy())),
            arara_core::motion::Cached::Missing => QString::default(),
            arara_core::motion::Cached::Unknown => {
                self.enqueue_motion(album_id, artist, title);
                QString::default()
            }
        }
    }

    pub fn download_all_motion_covers(mut self: Pin<&mut Self>) {
        if !self.motion_enabled() {
            return;
        }
        let Some(db) = self.db.as_ref() else { return };
        let dir = self.motion_dir();
        let t = now();
        let todo: Vec<(i64, String, String)> = db.conn.prepare(
            "SELECT al.id, COALESCE(ar.name, ''), al.title FROM albums al LEFT JOIN artists ar ON ar.id = al.artist_id
             WHERE al.title <> '' AND EXISTS (SELECT 1 FROM tracks t WHERE t.album_id = al.id) ORDER BY al.added_at DESC",
        ).and_then(|mut st| st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?.collect()).unwrap_or_default();
        let todo: Vec<_> = todo.into_iter()
            .filter(|(_, a, ti)| matches!(arara_core::motion::cached(db, &dir, a, ti, t), arara_core::motion::Cached::Unknown))
            .collect();
        if todo.is_empty() {
            let qt = self.qt_thread();
            let _ = qt.queue(|o| o.motion_progress(0, 0, 0));
            return;
        }
        for (id, a, ti) in todo {
            self.as_mut().enqueue_motion(id, a, ti);
        }
        let total = self.motion.as_ref().map_or(0, |q| q.total.load(std::sync::atomic::Ordering::Relaxed));
        self.as_mut().motion_progress(0, total, 0);
    }

    pub fn clear_motion_covers(self: Pin<&mut Self>) -> i32 {
        let Some(db) = self.db.as_ref() else { return 0 };
        arara_core::motion::clear(db, &self.motion_dir()) as i32
    }

    pub fn motion_cache_json(&self) -> QString {
        let dir = self.motion_dir();
        let files = std::fs::read_dir(&dir).map(|rd| rd.flatten().filter(|e| e.path().extension().is_some_and(|x| x == "mp4")).count()).unwrap_or(0);
        qs(&json!({ "files": files, "bytes": arara_core::motion::disk_usage(&dir) }).to_string())
    }

    pub fn tag_json(&self, tag: &QString, exclude_artist: i64) -> QString {
        let Some(db) = &self.db else { return qs("null") };
        let tag = tag.to_string();
        let exclude = (exclude_artist >= 0).then_some(exclude_artist);
        let Ok(m) = arara_core::similar::matches(db, &tag, exclude, 200) else { return qs("null") };
        let artists = db.artists().unwrap_or_default();
        let albums = db.albums().unwrap_or_default();
        let artist_v: Vec<_> = m.artists.iter().filter_map(|(id, _)| artists.iter().find(|a| a.id == *id))
            .take(30)
            .map(|a| json!({ "id": a.id, "name": a.name, "albums": a.album_count, "cover": self.cover(&a.cover_hash, 256) }))
            .collect();
        let album_v: Vec<_> = m.albums.iter().filter_map(|(id, _)| albums.iter().find(|a| a.id == *id)).take(30).map(|a| self.album_value(a)).collect();
        let mut tracks = db.tracks_by_ids(&m.tracks).unwrap_or_default();
        tracks.sort_by_key(|t| m.tracks.iter().position(|i| *i == t.id));
        let v = json!({
            "tag": tag,
            "artists": artist_v, "artistTotal": m.artists.len(),
            "albums": album_v, "albumTotal": m.albums.len(),
            "tracks": tracks.iter().map(|t| self.track_value(t)).collect::<Vec<_>>(), "trackTotal": m.track_total,
        });
        qs(&v.to_string())
    }

    pub fn request_tag_online(self: Pin<&mut Self>, tag: &QString, area: &QString) {
        let tag = tag.to_string();
        let area = area.to_string();
        let qt = self.qt_thread();
        if !self.online_allowed() || tag.trim().is_empty() {
            let _ = qt.queue(move |o| o.tag_online(qs(&tag), qs("null")));
            return;
        }
        let db_path = self.db_path.clone();
        std::thread::spawn(move || {
            let Ok(db) = Db::open(&db_path) else { return };
            let key = format!("{tag}\u{1f}{area}");
            let data = arara_core::info::cached_or_fetch(&db, "tag", &key, now(), false, || {
                arara_core::similar::fetch_tag_artists(&tag, Some(&area))
            });
            let s = data.to_string();
            let _ = qt.queue(move |o| o.tag_online(qs(&tag), qs(&s)));
        });
    }

    // ---------- editing a song ----------

    pub fn editable_json(&self, track_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("null") };
        let Ok(Some(f)) = arara_core::edit::fields(db, track_id) else { return qs("null") };
        let mut v = serde_json::to_value(&f).unwrap_or(json!(null));
        v["cover"] = json!(self.cover(&f.cover_hash, 640));
        qs(&v.to_string())
    }

    pub fn save_track_edit(self: Pin<&mut Self>, track_id: i64, json: &QString, cover: &QString, write_file: bool) {
        let qt = self.qt_thread();
        let edit: arara_core::edit::TrackEdit = match serde_json::from_str(&json.to_string()) {
            Ok(e) => e,
            Err(e) => {
                let msg = json!({ "trackId": track_id, "error": format!("dados inválidos: {e}") }).to_string();
                let _ = qt.queue(move |o| o.track_edited(track_id, qs(&msg)));
                return;
            }
        };
        let cover = cover.to_string();
        let cover = (!cover.is_empty()).then(|| remote::url_to_path(&cover));
        let (db_path, covers_dir) = (self.db_path.clone(), self.covers_dir.clone());
        // Files may sit on a slow or locked disk: never touch them on the UI thread.
        std::thread::spawn(move || {
            let res = (|| -> Result<arara_core::edit::EditOutcome, String> {
                let db = Db::open(&db_path).map_err(|e| e.to_string())?;
                let covers = CoverCache::new(&covers_dir).map_err(|e| e.to_string())?;
                let bytes = match &cover {
                    Some(p) => {
                        Some(std::fs::read(p).map_err(|e| format!("não foi possível abrir a imagem: {e}"))?)
                    }
                    None => None,
                };
                arara_core::edit::apply(&db, &covers, track_id, edit, bytes, write_file).map_err(|e| match e {
                    arara_core::Error::Image(_) => "o arquivo escolhido não é uma imagem".to_string(),
                    e => e.to_string(),
                })
            })();
            let _ = qt.queue(move |mut o| {
                let mut v = match res {
                    Ok(out) => serde_json::to_value(&out).unwrap_or(json!({})),
                    Err(e) => json!({ "trackId": track_id, "error": e }),
                };
                if v.get("error").is_none() {
                    o.as_mut().refresh_counts();
                    o.as_mut().library_changed();
                    o.as_mut().playlists_changed();
                }
                let track = o.db.as_ref().and_then(|d| d.track(track_id).ok().flatten()).map(|t| o.track_value(&t));
                v["track"] = track.unwrap_or(json!(null));
                o.as_mut().track_edited(track_id, qs(&v.to_string()));
            });
        });
    }

    pub fn revert_track_edit(mut self: Pin<&mut Self>, track_id: i64) -> bool {
        let Some(db) = &self.db else { return false };
        let undone = arara_core::edit::revert(db, track_id).unwrap_or(false);
        if undone {
            // Local: re-read the file now. Server songs come back on the next sync.
            self.as_mut().rescan();
        }
        undone
    }

    pub fn show_in_folder(&self, track_id: i64) -> bool {
        let Some(db) = &self.db else { return false };
        let Ok(Some(t)) = db.track(track_id) else { return false };
        if remote::is_remote(&t.path) {
            return false;
        }
        desktop::show_in_folder(&t.path)
    }

    pub fn lyrics_text(&self, track_id: i64) -> QString {
        let Some(db) = &self.db else { return qs("") };
        match db.cached_lyrics(track_id).ok().flatten() {
            Some((_, Some(synced), _)) => qs(&lyrics::lrc_to_plain(&synced)),
            Some((_, None, Some(plain))) => qs(&plain),
            _ => qs(""),
        }
    }

    pub fn request_analysis(self: Pin<&mut Self>, track_id: i64) {
        let qt = self.qt_thread();
        let db_path = self.db_path.clone();
        // One analysis at a time: decoding is CPU-heavy and they come in pairs.
        static BUSY: std::sync::Mutex<()> = std::sync::Mutex::new(());
        std::thread::spawn(move || {
            let _g = BUSY.lock();
            let res = Db::open(&db_path).ok().and_then(|db| arara_core::analysis::cached_or_analyze(&db, track_id));
            let s = res.map(|a| serde_json::to_string(&a).unwrap_or_else(|_| "null".into())).unwrap_or_else(|| "null".into());
            let _ = qt.queue(move |o| o.analysis_ready(track_id, qs(&s)));
        });
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

    pub fn mpris_rate(&self, rate: f64) {
        if let Some(m) = &self.mpris {
            m.set_rate(rate)
        }
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
        // Turning info lookups (back) on starts the background run.
        if matches!(key.to_string().as_str(), "onlineinfo" | "infoprefetch" | "infofiles") && value.to_string() == "1" {
            let _ = self.qt_thread().queue(|o| o.prefetch_info());
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
            const IMAGES: &[&str] = &["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG"];
            let filters: &[(&str, &[&str])] = if directory {
                &[]
            } else if purpose.starts_with("cover:") || purpose == "trackcover" {
                &[("Imagens", IMAGES), ("Todos os arquivos", &["*"])]
            } else {
                &[("Exportações de playlists", EXPORTS), ("Todos os arquivos", &["*"])]
            };
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
