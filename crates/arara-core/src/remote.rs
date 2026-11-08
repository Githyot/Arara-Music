//! Remote libraries: Subsonic API servers (Navidrome, Gonic, Airsonic, Ampache…)
//! and Jellyfin.
//!
//! A sync pulls the server's whole catalog in pages of 500 (a handful of
//! requests, not one per album), downloads each album cover once into the same
//! thumbnail cache local files use, and mirrors everything into `tracks` with
//! `remote://<server>/<item>` paths. From then on the remote library opens as
//! fast as the local one, stays browsable offline, and a re-sync only rewrites
//! the tracks whose metadata actually changed (each row keeps a signature).
//!
//! Credentials: only derived tokens are stored (Subsonic's salted MD5 token,
//! Jellyfin's access token), never the password.

use crate::covers::CoverCache;
use crate::db::{self, AlbumRow, Db, NewTrack};
use md5::{Digest, Md5};
use rayon::prelude::*;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::time::{Duration, Instant};

pub const PREFIX: &str = "remote://";
const VERSION: &str = env!("CARGO_PKG_VERSION");
const PAGE: usize = 500;
const SUBSONIC_API: &str = "1.16.1";

pub type R<T> = std::result::Result<T, String>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Subsonic,
    Jellyfin,
}

impl Kind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Kind::Subsonic => "subsonic",
            Kind::Jellyfin => "jellyfin",
        }
    }
    pub fn parse(s: &str) -> Option<Kind> {
        match s.to_ascii_lowercase().as_str() {
            "subsonic" | "navidrome" => Some(Kind::Subsonic),
            "jellyfin" => Some(Kind::Jellyfin),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Auth {
    Subsonic { salt: String, token: String },
    Jellyfin { token: String, user_id: String, device_id: String },
}

#[derive(Clone, Debug)]
pub struct Server {
    pub id: i64,
    pub kind: Kind,
    pub name: String,
    pub url: String,
    pub username: String,
    pub auth: Auth,
    pub last_sync: Option<i64>,
    pub track_count: i64,
    pub last_error: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct RemoteTrack {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album_artist: String,
    pub album: Option<String>,
    pub cover_id: Option<String>,
    pub track_no: Option<u32>,
    pub disc_no: Option<u32>,
    pub year: Option<u32>,
    pub duration_ms: i64,
    pub genre: Option<String>,
    pub explicit: Option<bool>,
}

impl RemoteTrack {
    /// Cheap fingerprint of the metadata we store; unchanged tracks are skipped on re-sync.
    fn signature(&self) -> i64 {
        let s = format!(
            "{}\u{1}{}\u{1}{}\u{1}{:?}\u{1}{:?}\u{1}{:?}\u{1}{:?}\u{1}{}\u{1}{:?}\u{1}{:?}",
            self.title, self.artist, self.album_artist, self.album, self.track_no, self.disc_no, self.year, self.duration_ms, self.genre,
            self.explicit
        );
        let h = blake3::hash(s.as_bytes());
        i64::from_le_bytes(h.as_bytes()[..8].try_into().unwrap())
    }
}

#[derive(Clone, Debug, Default)]
pub struct SyncStats {
    pub tracks: usize,
    pub written: usize,
    pub removed: usize,
    pub covers: usize,
    pub elapsed_ms: u128,
}

pub fn remote_path(server_id: i64, item: &str) -> String {
    format!("{PREFIX}{server_id}/{item}")
}

pub fn parse_path(path: &str) -> Option<(i64, &str)> {
    let (s, id) = path.strip_prefix(PREFIX)?.split_once('/')?;
    Some((s.parse().ok()?, id))
}

pub fn is_remote(path: &str) -> bool {
    path.starts_with(PREFIX)
}

fn normalize_url(url: &str) -> String {
    let u = url.trim().trim_end_matches('/');
    if u.starts_with("http://") || u.starts_with("https://") {
        u.to_string()
    } else {
        format!("https://{u}")
    }
}

/// Percent-encode for a URL query value / path segment.
fn enc(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// `file://` URL for a local path, escaping only what would break URL parsing.
pub fn file_url(path: &str) -> String {
    let mut out = String::from("file://");
    // Windows: C:\Music\a.mp3 -> file:///C:/Music/a.mp3
    let win = cfg!(windows) || path.as_bytes().get(1) == Some(&b':');
    if win && !path.starts_with('/') {
        out.push('/');
    }
    for c in path.chars() {
        if win && c == '\\' {
            out.push('/');
            continue;
        }
        match c {
            '%' => out.push_str("%25"),
            '#' => out.push_str("%23"),
            '?' => out.push_str("%3F"),
            _ => out.push(c),
        }
    }
    out
}

/// Local path from a `file://` URL (or a plain path), undoing [`file_url`].
pub fn url_to_path(u: &str) -> String {
    let p = u.strip_prefix("file://").unwrap_or(u);
    let b = p.as_bytes();
    // file:///C:/x -> C:/x
    let p = if b.len() > 2 && b[0] == b'/' && b[2] == b':' && b[1].is_ascii_alphabetic() { &p[1..] } else { p };
    if cfg!(windows) {
        p.replace('/', "\\")
    } else {
        p.to_string()
    }
}

fn random_hex(n: usize) -> String {
    let seed = format!("{:?}{}{:?}", std::time::SystemTime::now(), std::process::id(), Instant::now());
    blake3::hash(seed.as_bytes()).to_hex()[..n].to_string()
}

/// Subsonic token auth: md5(password + salt), hex.
pub fn subsonic_token(password: &str, salt: &str) -> String {
    let d = Md5::digest(format!("{password}{salt}").as_bytes());
    d.iter().map(|b| format!("{b:02x}")).collect()
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(8))
        .timeout_read(Duration::from_secs(60))
        .user_agent(&format!("AraraMusic/{VERSION}"))
        .build()
}

fn http_err(e: ureq::Error) -> String {
    match e {
        ureq::Error::Status(401 | 403, _) => "usuário ou senha incorretos".into(),
        ureq::Error::Status(code, r) => format!("o servidor respondeu {code} {}", r.status_text()),
        // Don't echo the URL: it carries the auth token.
        ureq::Error::Transport(t) => match t.kind() {
            ureq::ErrorKind::Dns => "endereço não encontrado".into(),
            ureq::ErrorKind::ConnectionFailed if t.to_string().contains("tls") => {
                "falha no TLS (o servidor usa http:// em vez de https://?)".into()
            }
            ureq::ErrorKind::ConnectionFailed | ureq::ErrorKind::Io => "não foi possível conectar ao servidor".into(),
            k => format!("erro de rede: {k}"),
        },
    }
}

fn json_body(r: ureq::Response) -> R<Value> {
    r.into_json().map_err(|e| format!("resposta inválida do servidor: {e}"))
}

fn bytes_body(r: ureq::Response) -> Option<Vec<u8>> {
    if r.content_type().contains("json") || r.content_type().contains("xml") {
        return None; // Subsonic reports "not found" as a JSON/XML error body
    }
    let mut buf = Vec::new();
    r.into_reader().take(20 << 20).read_to_end(&mut buf).ok()?;
    (!buf.is_empty()).then_some(buf)
}

/// String or number → String (servers disagree on id types).
fn vs(v: &Value) -> Option<String> {
    match v {
        Value::String(s) if !s.is_empty() => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

fn vu32(v: &Value) -> Option<u32> {
    v.as_u64().map(|n| n as u32).filter(|n| *n > 0)
}

// ---------- Subsonic ----------

fn subsonic_song(v: &Value, album_artist_fallback: Option<&str>) -> Option<RemoteTrack> {
    let id = vs(&v["id"])?;
    if v["isDir"].as_bool() == Some(true) || v["isVideo"].as_bool() == Some(true) {
        return None;
    }
    let artist = vs(&v["artist"]).unwrap_or_default();
    // OpenSubsonic (Navidrome) exposes the album artist; plain Subsonic doesn't.
    let album_artist = vs(&v["displayAlbumArtist"])
        .or_else(|| vs(&v["albumArtists"][0]["name"]))
        .or_else(|| album_artist_fallback.map(str::to_owned))
        .unwrap_or_else(|| artist.clone());
    Some(RemoteTrack {
        title: vs(&v["title"]).unwrap_or_else(|| id.clone()),
        id,
        artist,
        album_artist,
        album: vs(&v["album"]),
        cover_id: vs(&v["coverArt"]),
        track_no: vu32(&v["track"]),
        disc_no: vu32(&v["discNumber"]),
        year: vu32(&v["year"]),
        duration_ms: v["duration"].as_i64().unwrap_or(0) * 1000,
        genre: vs(&v["genre"]),
        // OpenSubsonic: "explicit" | "clean" | "".
        explicit: v["explicitStatus"].as_str().and_then(crate::explicit::from_tag_value),
    })
}

// ---------- Jellyfin ----------

fn jellyfin_item(v: &Value) -> Option<RemoteTrack> {
    let id = vs(&v["Id"])?;
    let artist = vs(&v["Artists"][0]).or_else(|| vs(&v["AlbumArtist"])).unwrap_or_default();
    let cover_id = if v["AlbumPrimaryImageTag"].is_string() {
        vs(&v["AlbumId"])
    } else if v["ImageTags"]["Primary"].is_string() {
        Some(id.clone())
    } else {
        None
    };
    Some(RemoteTrack {
        title: vs(&v["Name"]).unwrap_or_else(|| id.clone()),
        id,
        album_artist: vs(&v["AlbumArtist"]).unwrap_or_else(|| artist.clone()),
        artist,
        album: vs(&v["Album"]),
        cover_id,
        track_no: vu32(&v["IndexNumber"]),
        disc_no: vu32(&v["ParentIndexNumber"]),
        year: vu32(&v["ProductionYear"]),
        duration_ms: v["RunTimeTicks"].as_i64().unwrap_or(0) / 10_000,
        genre: vs(&v["Genres"][0]),
        // Jellyfin has no advisory field of its own; some libraries carry it as
        // a tag ("Explicit") or in OfficialRating.
        explicit: v["Tags"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|t| t.as_str())
            .find_map(crate::explicit::from_tag_value)
            .or_else(|| v["OfficialRating"].as_str().and_then(crate::explicit::from_tag_value)),
    })
}

fn jellyfin_header(device_id: &str, token: Option<&str>) -> String {
    let mut h = format!(
        "MediaBrowser Client=\"Arara Music\", Device=\"Linux\", DeviceId=\"{device_id}\", Version=\"{VERSION}\""
    );
    if let Some(t) = token {
        h.push_str(&format!(", Token=\"{t}\""));
    }
    h
}

// ---------- client ----------

pub struct Client {
    pub server: Server,
    agent: ureq::Agent,
}

impl Client {
    pub fn new(server: Server) -> Self {
        Self { server, agent: agent() }
    }

    fn subsonic(&self, method: &str, q: &[(&str, &str)]) -> R<Value> {
        let Auth::Subsonic { salt, token } = &self.server.auth else { return Err("credenciais inválidas".into()) };
        let mut req = self
            .agent
            .get(&format!("{}/rest/{method}", self.server.url))
            .query("u", &self.server.username)
            .query("t", token)
            .query("s", salt)
            .query("v", SUBSONIC_API)
            .query("c", "arara")
            .query("f", "json");
        for (k, v) in q {
            req = req.query(k, v);
        }
        let v = json_body(req.call().map_err(http_err)?)?;
        let r = &v["subsonic-response"];
        if r["status"] == "ok" {
            Ok(r.clone())
        } else if r.is_null() {
            Err("isto não parece um servidor Subsonic/Navidrome".into())
        } else {
            Err(match r["error"]["code"].as_i64() {
                Some(40) | Some(41) => "usuário ou senha incorretos".into(),
                _ => r["error"]["message"].as_str().unwrap_or("erro do servidor").to_string(),
            })
        }
    }

    fn jellyfin(&self, path: &str, q: &[(&str, &str)]) -> R<Value> {
        let Auth::Jellyfin { token, device_id, .. } = &self.server.auth else { return Err("credenciais inválidas".into()) };
        let mut req = self
            .agent
            .get(&format!("{}{path}", self.server.url))
            .set("Authorization", &jellyfin_header(device_id, Some(token)));
        for (k, v) in q {
            req = req.query(k, v);
        }
        json_body(req.call().map_err(http_err)?)
    }

    /// Whole catalog, in pages. `progress` gets the running count.
    pub fn fetch_tracks(&self, progress: &mut dyn FnMut(usize)) -> R<Vec<RemoteTrack>> {
        let mut out = Vec::new();
        let mut seen = HashSet::new();
        let mut push = |t: RemoteTrack, out: &mut Vec<RemoteTrack>| {
            if seen.insert(t.id.clone()) {
                out.push(t)
            }
        };
        match self.server.kind {
            Kind::Subsonic => {
                // search3 with an empty query lists every song (Navidrome, Gonic, Airsonic-Advanced).
                let mut off = 0;
                loop {
                    let o = off.to_string();
                    let r = self.subsonic(
                        "search3",
                        &[("query", ""), ("songCount", "500"), ("songOffset", &o), ("artistCount", "0"), ("albumCount", "0")],
                    )?;
                    let songs = r["searchResult3"]["song"].as_array().cloned().unwrap_or_default();
                    let before = out.len();
                    for s in &songs {
                        if let Some(t) = subsonic_song(s, None) {
                            push(t, &mut out);
                        }
                    }
                    progress(out.len());
                    if songs.len() < PAGE || out.len() == before {
                        break;
                    }
                    off += songs.len();
                }
                if out.is_empty() {
                    // Servers without empty-query search: walk the album list instead.
                    let mut ids = Vec::new();
                    let mut off = 0;
                    loop {
                        let o = off.to_string();
                        let r = self.subsonic("getAlbumList2", &[("type", "alphabeticalByName"), ("size", "500"), ("offset", &o)])?;
                        let albums = r["albumList2"]["album"].as_array().cloned().unwrap_or_default();
                        ids.extend(albums.iter().filter_map(|a| vs(&a["id"])));
                        if albums.len() < PAGE {
                            break;
                        }
                        off += albums.len();
                    }
                    for id in ids {
                        let r = self.subsonic("getAlbum", &[("id", &id)])?;
                        let aa = vs(&r["album"]["artist"]);
                        for s in r["album"]["song"].as_array().into_iter().flatten() {
                            if let Some(t) = subsonic_song(s, aa.as_deref()) {
                                push(t, &mut out);
                            }
                        }
                        progress(out.len());
                    }
                }
            }
            Kind::Jellyfin => {
                let Auth::Jellyfin { user_id, .. } = &self.server.auth else { return Err("credenciais inválidas".into()) };
                let path = format!("/Users/{user_id}/Items");
                let mut start = 0;
                loop {
                    let s = start.to_string();
                    let v = self.jellyfin(
                        &path,
                        &[
                            ("IncludeItemTypes", "Audio"),
                            ("Recursive", "true"),
                            ("Fields", "ProductionYear,ParentIndexNumber,Genres,Tags,OfficialRating"),
                            ("SortBy", "AlbumArtist,Album,ParentIndexNumber,IndexNumber"),
                            ("EnableUserData", "false"),
                            ("StartIndex", &s),
                            ("Limit", "500"),
                        ],
                    )?;
                    let items = v["Items"].as_array().cloned().unwrap_or_default();
                    for it in &items {
                        if let Some(t) = jellyfin_item(it) {
                            push(t, &mut out);
                        }
                    }
                    progress(out.len());
                    let total = v["TotalRecordCount"].as_u64().unwrap_or(0) as usize;
                    start += items.len();
                    if items.len() < PAGE || start >= total {
                        break;
                    }
                }
            }
        }
        Ok(out)
    }

    /// Cover image bytes (640 px), or None.
    pub fn cover(&self, cover_id: &str) -> Option<Vec<u8>> {
        let r = match (&self.server.kind, &self.server.auth) {
            (Kind::Subsonic, Auth::Subsonic { salt, token }) => self
                .agent
                .get(&format!("{}/rest/getCoverArt", self.server.url))
                .query("id", cover_id)
                .query("size", "640")
                .query("u", &self.server.username)
                .query("t", token)
                .query("s", salt)
                .query("v", SUBSONIC_API)
                .query("c", "arara")
                .call(),
            (Kind::Jellyfin, Auth::Jellyfin { token, device_id, .. }) => self
                .agent
                .get(&format!("{}/Items/{}/Images/Primary", self.server.url, enc(cover_id)))
                .query("maxWidth", "640")
                .query("quality", "90")
                .set("Authorization", &jellyfin_header(device_id, Some(token)))
                .call(),
            _ => return None,
        };
        bytes_body(r.ok()?)
    }
}

/// Direct stream URL for a remote item (original file, no transcoding).
pub fn stream_url(s: &Server, item: &str) -> String {
    match &s.auth {
        Auth::Subsonic { salt, token } => format!(
            "{}/rest/stream?id={}&u={}&t={token}&s={salt}&v={SUBSONIC_API}&c=arara",
            s.url,
            enc(item),
            enc(&s.username)
        ),
        Auth::Jellyfin { token, .. } => format!("{}/Audio/{}/stream?static=true&api_key={token}", s.url, enc(item)),
    }
}

// ---------- login ----------

/// Checks the credentials and returns (normalized url, auth tokens, server display name).
pub fn login(kind: Kind, url: &str, username: &str, password: &str) -> R<(String, Auth, String)> {
    let u = url.trim();
    if !u.starts_with("http://") && !u.starts_with("https://") {
        // No scheme typed: prefer https, but home servers on a LAN IP are usually plain http.
        return match login_at(kind, normalize_url(u), username, password) {
            Err(e) if e.starts_with("falha no TLS") || e.starts_with("não foi possível conectar") => {
                login_at(kind, format!("http://{}", u.trim_end_matches('/')), username, password)
            }
            r => r,
        };
    }
    login_at(kind, normalize_url(u), username, password)
}

fn login_at(kind: Kind, url: String, username: &str, password: &str) -> R<(String, Auth, String)> {
    let host = url.split("://").nth(1).unwrap_or(&url).split('/').next().unwrap_or("").to_string();
    match kind {
        Kind::Subsonic => {
            let salt = random_hex(12);
            let auth = Auth::Subsonic { token: subsonic_token(password, &salt), salt };
            let c = Client::new(Server {
                id: 0,
                kind,
                name: String::new(),
                url: url.clone(),
                username: username.into(),
                auth: auth.clone(),
                last_sync: None,
                track_count: 0,
                last_error: None,
            });
            let r = c.subsonic("ping", &[])?;
            let name = match r["type"].as_str() {
                Some(t) if !t.is_empty() => {
                    let mut c = t.chars();
                    let t: String = c.next().map(|f| f.to_uppercase().chain(c).collect()).unwrap_or_default();
                    format!("{t} · {host}")
                }
                _ => host,
            };
            Ok((url, auth, name))
        }
        Kind::Jellyfin => {
            let device_id = random_hex(16);
            let a = agent();
            let r = a
                .post(&format!("{url}/Users/AuthenticateByName"))
                .set("Authorization", &jellyfin_header(&device_id, None))
                .send_json(serde_json::json!({ "Username": username, "Pw": password }))
                .map_err(http_err)?;
            let v = json_body(r)?;
            let token = vs(&v["AccessToken"]).ok_or("o servidor não devolveu um token")?;
            let user_id = vs(&v["User"]["Id"]).ok_or("o servidor não devolveu o usuário")?;
            let name = a
                .get(&format!("{url}/System/Info/Public"))
                .call()
                .ok()
                .and_then(|r| r.into_json::<Value>().ok())
                .and_then(|v| vs(&v["ServerName"]))
                .unwrap_or(host);
            Ok((url, Auth::Jellyfin { token, user_id, device_id }, name))
        }
    }
}

// ---------- storage ----------

fn row_to_server(r: &rusqlite::Row) -> rusqlite::Result<Option<Server>> {
    let kind: String = r.get(1)?;
    let auth: String = r.get(5)?;
    let (Some(kind), Ok(auth)) = (Kind::parse(&kind), serde_json::from_str::<Auth>(&auth)) else { return Ok(None) };
    Ok(Some(Server {
        id: r.get(0)?,
        kind,
        name: r.get(2)?,
        url: r.get(3)?,
        username: r.get(4)?,
        auth,
        last_sync: r.get(6)?,
        track_count: r.get(7)?,
        last_error: r.get(8)?,
    }))
}

const SERVER_COLS: &str = "id, kind, name, url, username, auth, last_sync, track_count, last_error";

pub fn servers(db: &Db) -> crate::Result<Vec<Server>> {
    let mut st = db.conn.prepare(&format!("SELECT {SERVER_COLS} FROM servers ORDER BY name COLLATE NOCASE"))?;
    let rows = st.query_map([], row_to_server)?;
    Ok(rows.flatten().flatten().collect())
}

pub fn server(db: &Db, id: i64) -> crate::Result<Option<Server>> {
    Ok(db
        .conn
        .query_row(&format!("SELECT {SERVER_COLS} FROM servers WHERE id=?1"), [id], row_to_server)
        .optional()?
        .flatten())
}

pub fn add_server(db: &Db, kind: Kind, name: &str, url: &str, username: &str, auth: &Auth) -> crate::Result<i64> {
    db.conn.execute(
        "INSERT INTO servers(kind, name, url, username, auth) VALUES (?1,?2,?3,?4,?5)",
        params![kind.as_str(), name, url, username, serde_json::to_string(auth).unwrap()],
    )?;
    Ok(db.conn.last_insert_rowid())
}

pub fn rename_server(db: &Db, id: i64, name: &str) -> crate::Result<()> {
    db.conn.execute("UPDATE servers SET name=?1 WHERE id=?2", params![name, id])?;
    Ok(())
}

pub fn set_error(db: &Db, id: i64, err: Option<&str>) -> crate::Result<()> {
    db.conn.execute("UPDATE servers SET last_error=?1 WHERE id=?2", params![err, id])?;
    Ok(())
}

/// Removes the server and every track that came from it.
pub fn remove_server(db: &mut Db, id: i64) -> crate::Result<usize> {
    let _w = db::WRITER.lock().unwrap_or_else(|e| e.into_inner());
    let prefix = format!("{PREFIX}{id}/");
    let txn = db.conn.transaction()?;
    let n = db::delete_tracks_where(&txn, |p| p.starts_with(&prefix))?;
    txn.execute("DELETE FROM servers WHERE id=?1", [id])?;
    txn.commit()?;
    Ok(n)
}

pub fn server_albums(db: &Db, id: i64) -> crate::Result<Vec<AlbumRow>> {
    db.albums_with_path_prefix(&format!("{PREFIX}{id}/"))
}

/// Builds playable URLs for track paths (local files and remote items).
#[derive(Default, Clone)]
pub struct Resolver {
    servers: HashMap<i64, Server>,
}

impl Resolver {
    pub fn load(db: &Db) -> Self {
        Self { servers: servers(db).unwrap_or_default().into_iter().map(|s| (s.id, s)).collect() }
    }
    pub fn url(&self, path: &str) -> String {
        match parse_path(path) {
            Some((sid, item)) => self.servers.get(&sid).map(|s| stream_url(s, item)).unwrap_or_default(),
            None => file_url(path),
        }
    }
}

// ---------- sync ----------

pub fn sync(db: &mut Db, covers: &CoverCache, server: &Server, mut progress: impl FnMut(String)) -> R<SyncStats> {
    let t0 = Instant::now();
    let client = Client::new(server.clone());
    progress(format!("{}: conectando…", server.name));
    let tracks = client.fetch_tracks(&mut |n| progress(format!("{}: {n} faixas recebidas", server.name)))?;
    let e = |e: crate::Error| e.to_string();

    // Albums that still need a cover, keyed like the albums table (title, album artist).
    let key = |t: &RemoteTrack| {
        let aa = if t.album_artist.is_empty() { "Artista desconhecido".to_string() } else { t.album_artist.clone() };
        (t.album.clone().unwrap_or_default().to_lowercase(), aa.to_lowercase())
    };
    let have: HashSet<(String, String)> = {
        let mut st = db
            .conn
            .prepare("SELECT a.title, ar.name FROM albums a JOIN artists ar ON ar.id=a.artist_id WHERE a.cover_hash IS NOT NULL")
            .map_err(|x| x.to_string())?;
        let rows = st
            .query_map([], |r| Ok((r.get::<_, String>(0)?.to_lowercase(), r.get::<_, String>(1)?.to_lowercase())))
            .map_err(|x| x.to_string())?;
        rows.flatten().collect()
    };
    let mut want: HashMap<(String, String), String> = HashMap::new();
    for t in tracks.iter().filter(|t| t.album.is_some()) {
        if let Some(c) = &t.cover_id {
            let k = key(t);
            if !have.contains(&k) {
                want.entry(k).or_insert_with(|| c.clone());
            }
        }
    }
    if !want.is_empty() {
        progress(format!("{}: baixando {} capas…", server.name, want.len()));
    }
    let pool = rayon::ThreadPoolBuilder::new().num_threads(6).build().map_err(|x| x.to_string())?;
    let mut got: HashMap<(String, String), String> = pool.install(|| {
        want.par_iter()
            .filter_map(|(k, cid)| client.cover(cid).and_then(|b| covers.store(&b).ok()).map(|h| (k.clone(), h)))
            .collect()
    });
    let mut stats = SyncStats { tracks: tracks.len(), covers: got.len(), ..Default::default() };

    progress(format!("{}: salvando…", server.name));
    let known = db.known_files().map_err(e)?;
    let _w = db::WRITER.lock().unwrap_or_else(|x| x.into_inner());
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64;
    let txn = db.conn.transaction().map_err(|x| x.to_string())?;
    let mut seen = HashSet::with_capacity(tracks.len());
    for t in &tracks {
        let path = remote_path(server.id, &t.id);
        let sig = t.signature();
        let cover = got.remove(&key(t));
        if known.get(&path) == Some(&(0, sig)) && cover.is_none() {
            seen.insert(path);
            continue;
        }
        db::upsert_track(
            &txn,
            &NewTrack {
                path: &path,
                mtime: 0,
                size: sig,
                title: &t.title,
                artist: &t.artist,
                album_artist: &t.album_artist,
                album: t.album.as_deref(),
                track_no: t.track_no,
                disc_no: t.disc_no,
                year: t.year,
                duration_ms: t.duration_ms,
                track_gain: None,
                album_gain: None,
                cover_hash: cover.as_deref(),
                genre: t.genre.as_deref(),
                composer: None,
                format: None, sample_rate: None, bit_depth: None, bitrate: None,
                explicit: t.explicit, art_hash: None, folder_art: None,
            },
            now,
        )
        .map_err(e)?;
        stats.written += 1;
        seen.insert(path);
    }
    let prefix = format!("{PREFIX}{}/", server.id);
    stats.removed = db::delete_tracks_where(&txn, |p| p.starts_with(&prefix) && !seen.contains(p)).map_err(e)?;
    txn.execute(
        "UPDATE servers SET last_sync=?1, track_count=?2, last_error=NULL WHERE id=?3",
        params![now, tracks.len() as i64, server.id],
    )
    .map_err(|x| x.to_string())?;
    crate::dupes::mark(&txn).map_err(e)?;
    txn.commit().map_err(|x| x.to_string())?;
    stats.elapsed_ms = t0.elapsed().as_millis();
    Ok(stats)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subsonic_token_matches_spec_example() {
        // Example from the Subsonic API documentation.
        assert_eq!(subsonic_token("sesame", "c19b2d"), "26719a1196d2a940705a59634eb18eab");
    }

    #[test]
    fn paths_round_trip() {
        let p = remote_path(3, "al-12/x");
        assert_eq!(parse_path(&p), Some((3, "al-12/x")));
        assert_eq!(parse_path("/home/a.mp3"), None);
        assert_eq!(file_url("/m/a #1?.mp3"), "file:///m/a %231%3F.mp3");
    }

    #[test]
    fn parses_subsonic_song() {
        let v: Value = serde_json::from_str(
            r#"{"id":"tr-1","title":"Garota","artist":"Tom","album":"Bossa","albumId":"al-1","coverArt":"al-1",
                "track":2,"discNumber":1,"year":1963,"duration":191,"displayAlbumArtist":"Vários"}"#,
        )
        .unwrap();
        let t = subsonic_song(&v, None).unwrap();
        assert_eq!(t.id, "tr-1");
        assert_eq!(t.album_artist, "Vários");
        assert_eq!(t.duration_ms, 191_000);
        assert_eq!(t.track_no, Some(2));
        assert_eq!(t.cover_id.as_deref(), Some("al-1"));
    }

    #[test]
    fn parses_jellyfin_item() {
        let v: Value = serde_json::from_str(
            r#"{"Id":"abc","Name":"Song","Artists":["A","B"],"AlbumArtist":"A","Album":"X","AlbumId":"alb",
                "AlbumPrimaryImageTag":"t","IndexNumber":5,"ParentIndexNumber":2,"ProductionYear":2001,"RunTimeTicks":1234560000}"#,
        )
        .unwrap();
        let t = jellyfin_item(&v).unwrap();
        assert_eq!((t.artist.as_str(), t.album_artist.as_str()), ("A", "A"));
        assert_eq!(t.cover_id.as_deref(), Some("alb"));
        assert_eq!(t.duration_ms, 123_456);
        assert_eq!((t.track_no, t.disc_no, t.year), (Some(5), Some(2), Some(2001)));
    }

    #[test]
    fn stream_urls() {
        let mut s = Server {
            id: 1,
            kind: Kind::Subsonic,
            name: "n".into(),
            url: "https://music.example".into(),
            username: "joão".into(),
            auth: Auth::Subsonic { salt: "s".into(), token: "t".into() },
            last_sync: None,
            track_count: 0,
            last_error: None,
        };
        assert_eq!(stream_url(&s, "a b"), "https://music.example/rest/stream?id=a%20b&u=jo%C3%A3o&t=t&s=s&v=1.16.1&c=arara");
        s.auth = Auth::Jellyfin { token: "k".into(), user_id: "u".into(), device_id: "d".into() };
        assert_eq!(stream_url(&s, "x"), "https://music.example/Audio/x/stream?static=true&api_key=k");
    }
}
