//! Details about a song, an album or an artist, for the info pages.
//!
//! Two sources:
//! * the file's own tags (read on demand with lofty: credits like producer,
//!   lyricist or engineer, label, ISRC, BPM, MusicBrainz ids, audio details);
//! * MusicBrainz + Wikipedia online (credits with roles, artist bio and photo,
//!   release label/date), fetched in the background at most once per second
//!   and cached in the `kv` table, so a page opens instantly the second time.
//!
//! Base URLs can be overridden with `ARARA_MB_URL`, `ARARA_WIKIDATA_URL` and
//! `ARARA_WIKI_URL` (used by `tools/mock_info_server.py` in tests).

use lofty::file::{AudioFile, TaggedFileExt};
use lofty::tag::{Accessor, ItemKey};
use serde_json::{json, Value};
use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::db::Db;

/// How long an online answer stays fresh (30 days); misses are retried after 3.
const FRESH_SECS: i64 = 30 * 24 * 3600;
const MISS_SECS: i64 = 3 * 24 * 3600;
const UA: &str = "AraraMusic/0.8 ( https://github.com/Githyot )";

// ---------------------------------------------------------------------------
// File tags
// ---------------------------------------------------------------------------

/// Credit roles found in tags, with their pt-BR label, in display order.
const TAG_ROLES: &[(ItemKey, &str)] = &[
    (ItemKey::Performer, "Intérprete"),
    (ItemKey::Composer, "Composição"),
    (ItemKey::Lyricist, "Letra"),
    (ItemKey::Writer, "Autoria"),
    (ItemKey::Arranger, "Arranjo"),
    (ItemKey::Conductor, "Regência"),
    (ItemKey::Producer, "Produção"),
    (ItemKey::Engineer, "Engenharia de som"),
    (ItemKey::MixEngineer, "Mixagem"),
    (ItemKey::MixDj, "DJ"),
    (ItemKey::Remixer, "Remix"),
    (ItemKey::OriginalArtist, "Artista original"),
    (ItemKey::OriginalLyricist, "Letra original"),
];

/// Split "A; B / C" multi-value strings the way taggers write them.
fn split_names(s: &str) -> Vec<String> {
    s.split([';', '\0'])
        .flat_map(|p| p.split(" / "))
        .map(|p| p.trim().to_owned())
        .filter(|p| !p.is_empty())
        .collect()
}

/// "Artista feat. Outro" / "A & B" → main artist + featured names.
pub fn split_artists(s: &str) -> (String, Vec<String>) {
    let lower = s.to_lowercase();
    for sep in [" feat. ", " feat ", " ft. ", " featuring ", " part. ", " com "] {
        if let Some(i) = lower.find(sep) {
            let main = s[..i].trim().to_owned();
            let rest = &s[i + sep.len()..];
            let guests = rest
                .split([',', '&'])
                .flat_map(|p| p.split(" e "))
                .map(|p| p.trim().trim_end_matches(')').trim().to_owned())
                .filter(|p| !p.is_empty())
                .collect();
            return (main.trim_end_matches('(').trim().to_owned(), guests);
        }
    }
    (s.trim().to_owned(), vec![])
}

fn credit(name: &str, role: &str, source: &str) -> Value {
    json!({ "name": name, "role": role, "source": source })
}

/// Everything the file itself says about the song: credits, extra tags and
/// audio properties. `{}` when the file can't be read (moved, remote).
pub fn file_details(path: &str) -> Value {
    let p = Path::new(path);
    let Ok(tagged) = lofty::read_from_path(p) else { return json!({}) };
    let props = tagged.properties();
    let size = std::fs::metadata(p).map(|m| m.len()).unwrap_or(0);
    let mut out = json!({
        "audio": {
            "bitrate": props.audio_bitrate(),
            "overallBitrate": props.overall_bitrate(),
            "sampleRate": props.sample_rate(),
            "bitDepth": props.bit_depth(),
            "channels": props.channels(),
            "durationMs": props.duration().as_millis() as u64,
            "size": size,
        },
        "credits": [],
        "fields": {},
        "mbid": {},
    });
    let Some(t) = tagged.primary_tag().or_else(|| tagged.first_tag()) else { return out };

    let mut credits = vec![];
    if let Some(a) = t.artist() {
        let (main, guests) = split_artists(&a);
        for n in split_names(&main) {
            credits.push(credit(&n, "Artista", "tag"));
        }
        for g in guests {
            credits.push(credit(&g, "Participação", "tag"));
        }
    }
    for (key, role) in TAG_ROLES {
        for v in t.get_strings(key) {
            for n in split_names(v) {
                // ID3 TMCL/TIPL keep "instrument\0name" pairs; lofty hands back "instrument:name" or the bare name.
                let (role, name) = match n.split_once(':') {
                    Some((r, nm)) if *key == ItemKey::Performer && !nm.trim().is_empty() => (instrument_pt(r.trim()), nm.trim().to_owned()),
                    _ => (role.to_string(), n.clone()),
                };
                if !credits.iter().any(|c| c["name"] == name.as_str() && c["role"] == role.as_str()) {
                    credits.push(credit(&name, &role, "tag"));
                }
            }
        }
    }
    out["credits"] = Value::Array(credits);

    let field = |k: &ItemKey| t.get_string(k).map(|s| s.trim().to_owned()).filter(|s| !s.is_empty());
    let mut fields = serde_json::Map::new();
    let pairs: &[(&str, ItemKey)] = &[
        ("label", ItemKey::Label),
        ("publisher", ItemKey::Publisher),
        ("copyright", ItemKey::CopyrightMessage),
        ("isrc", ItemKey::Isrc),
        ("bpm", ItemKey::Bpm),
        ("key", ItemKey::InitialKey),
        ("language", ItemKey::Language),
        ("comment", ItemKey::Comment),
        ("encoder", ItemKey::EncoderSoftware),
        ("recordingDate", ItemKey::RecordingDate),
        ("releaseDate", ItemKey::ReleaseDate),
        ("originalDate", ItemKey::OriginalReleaseDate),
        ("albumArtist", ItemKey::AlbumArtist),
        ("trackTotal", ItemKey::TrackTotal),
        ("discTotal", ItemKey::DiscTotal),
    ];
    for (name, key) in pairs {
        if let Some(v) = field(key) {
            fields.insert((*name).into(), v.into());
        }
    }
    if !fields.contains_key("bpm") {
        if let Some(v) = field(&ItemKey::IntegerBpm) {
            fields.insert("bpm".into(), v.into());
        }
    }
    if let Some(n) = t.track() {
        fields.insert("track".into(), n.into());
    }
    if let Some(n) = t.track_total() {
        fields.insert("trackTotal".into(), n.into());
    }
    if let Some(n) = t.disk() {
        fields.insert("disc".into(), n.into());
    }
    if let Some(n) = t.disk_total() {
        fields.insert("discTotal".into(), n.into());
    }
    out["fields"] = Value::Object(fields);
    out["mbid"] = json!({
        "recording": field(&ItemKey::MusicBrainzRecordingId),
        "release": field(&ItemKey::MusicBrainzReleaseId),
        "releaseGroup": field(&ItemKey::MusicBrainzReleaseGroupId),
        "artist": field(&ItemKey::MusicBrainzArtistId).map(|s| split_names(&s).into_iter().next().unwrap_or(s)),
    });
    out
}

/// A few common instrument names in Portuguese (MusicBrainz and TMCL use English).
pub fn instrument_pt(s: &str) -> String {
    let l = s.to_lowercase();
    let t = match l.as_str() {
        "vocals" | "vocal" | "lead vocals" => "Voz",
        "background vocals" | "backing vocals" => "Backing vocal",
        "guitar" | "electric guitar" => "Guitarra",
        "acoustic guitar" => "Violão",
        "bass guitar" | "bass" | "electric bass guitar" => "Baixo",
        "drums" | "drums (drum set)" | "drum set" => "Bateria",
        "piano" => "Piano",
        "keyboard" | "keyboards" => "Teclado",
        "synthesizer" => "Sintetizador",
        "percussion" => "Percussão",
        "violin" => "Violino",
        "cello" => "Violoncelo",
        "saxophone" => "Saxofone",
        "trumpet" => "Trompete",
        "organ" => "Órgão",
        "strings" => "Cordas",
        "programming" => "Programação",
        "turntables" => "Toca-discos",
        "accordion" => "Acordeão",
        "flute" => "Flauta",
        "harmonica" => "Gaita",
        "cavaquinho" => "Cavaquinho",
        "pandeiro" => "Pandeiro",
        _ => "",
    };
    if t.is_empty() {
        let mut c = s.chars();
        c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
    } else {
        t.into()
    }
}

// ---------------------------------------------------------------------------
// Online: MusicBrainz + Wikidata + Wikipedia
// ---------------------------------------------------------------------------

fn base(var: &str, default: &str) -> String {
    std::env::var(var).unwrap_or_else(|_| default.to_owned()).trim_end_matches('/').to_owned()
}

/// MusicBrainz asks for at most one request per second per client.
static LAST_MB: Mutex<Option<Instant>> = Mutex::new(None);

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new().timeout(Duration::from_secs(12)).user_agent(UA).build()
}

fn get_json(a: &ureq::Agent, url: &str) -> Option<Value> {
    a.get(url).call().ok()?.into_json().ok()
}

fn mb(a: &ureq::Agent, path: &str) -> Option<Value> {
    {
        let mut last = LAST_MB.lock().unwrap();
        if let Some(t) = *last {
            let wait = Duration::from_millis(1100).saturating_sub(t.elapsed());
            std::thread::sleep(wait);
        }
        *last = Some(Instant::now());
    }
    let sep = if path.contains('?') { '&' } else { '?' };
    get_json(a, &format!("{}/ws/2/{path}{sep}fmt=json", base("ARARA_MB_URL", "https://musicbrainz.org")))
}

fn enc(s: &str) -> String {
    let mut o = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => o.push(b as char),
            _ => o.push_str(&format!("%{b:02X}")),
        }
    }
    o
}

/// Lucene phrase for a MusicBrainz search, with its special characters escaped.
fn phrase(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        if "+-&|!(){}[]^\"~*?:\\/".contains(c) {
            o.push('\\');
        }
        o.push(c);
    }
    o.push('"');
    o
}

fn norm(s: &str) -> String {
    crate::import::norm(s)
}

fn s(v: &Value) -> Option<String> {
    v.as_str().map(str::to_owned).filter(|x| !x.is_empty())
}

/// Best search hit whose name matches ours (MusicBrainz scores fuzzy matches high too).
fn pick<'a>(hits: &'a [Value], field: &str, want: &str) -> Option<&'a Value> {
    let w = norm(want);
    hits.iter()
        .find(|h| norm(h[field].as_str().unwrap_or("")) == w)
        .or_else(|| hits.first().filter(|h| h["score"].as_i64().unwrap_or(0) >= 95))
}

/// Wikipedia summary (pt first, then en) for a Wikidata id: text, page link, photo URL.
fn wikipedia(a: &ureq::Agent, qid: &str) -> Option<Value> {
    let wd = get_json(a, &format!("{}/wiki/Special:EntityData/{qid}.json", base("ARARA_WIKIDATA_URL", "https://www.wikidata.org")))?;
    let links = &wd["entities"][qid]["sitelinks"];
    for lang in ["pt", "en"] {
        let Some(title) = s(&links[format!("{lang}wiki")]["title"]) else { continue };
        let url = format!(
            "{}/api/rest_v1/page/summary/{}",
            base("ARARA_WIKI_URL", &format!("https://{lang}.wikipedia.org")).replace("{lang}", lang),
            enc(&title.replace(' ', "_"))
        );
        if let Some(sum) = get_json(a, &url) {
            if let Some(text) = s(&sum["extract"]) {
                return Some(json!({
                    "text": text,
                    "lang": lang,
                    "url": s(&sum["content_urls"]["desktop"]["page"]).unwrap_or_else(|| format!("https://{lang}.wikipedia.org/wiki/{}", enc(&title.replace(' ', "_")))),
                    "image": s(&sum["thumbnail"]["source"]),
                }));
            }
        }
    }
    None
}

fn wikidata_id(rels: &Value) -> Option<String> {
    rels.as_array()?.iter().find_map(|r| {
        let u = r["url"]["resource"].as_str()?;
        (r["type"] == "wikidata").then(|| u.rsplit('/').next().unwrap_or("").to_owned()).filter(|q| q.starts_with('Q'))
    })
}

fn tag_names(v: &Value, limit: usize) -> Vec<String> {
    let mut g: Vec<(i64, String)> = v
        .as_array()
        .map(|a| a.iter().filter_map(|t| Some((t["count"].as_i64().unwrap_or(0), s(&t["name"])?))).collect())
        .unwrap_or_default();
    g.sort_by(|a, b| b.0.cmp(&a.0));
    g.into_iter().take(limit).map(|(_, n)| n).collect()
}

fn artist_type_pt(t: &str) -> &'static str {
    match t {
        "Person" => "Artista solo",
        "Group" => "Grupo",
        "Orchestra" => "Orquestra",
        "Choir" => "Coral",
        "Character" => "Personagem",
        _ => "",
    }
}

/// Lucene phrase for a MusicBrainz search query.
pub fn mb_phrase(s: &str) -> String {
    phrase(s)
}

/// MusicBrainz search (`artist`, `release-group`…), rate limited like the lookups.
pub fn mb_search(entity: &str, query: &str, limit: u32) -> Option<Value> {
    mb(&agent(), &format!("{entity}/?query={}&limit={limit}", enc(query)))
}

/// MusicBrainz artist type in Portuguese ("Group" → "Grupo").
pub fn artist_type(t: &str) -> &'static str {
    artist_type_pt(t)
}

/// Artist facts: type, country, active years, genres, Wikipedia bio and photo.
pub fn fetch_artist(name: &str, mbid: Option<&str>) -> Option<Value> {
    let a = agent();
    let id = match mbid {
        Some(id) => id.to_owned(),
        None => {
            let r = mb(&a, &format!("artist/?query=artist:{}&limit=5", enc(&phrase(name))))?;
            let hits = r["artists"].as_array()?;
            s(&pick(hits, "name", name)?["id"])?
        }
    };
    let d = mb(&a, &format!("artist/{id}?inc=genres+tags+url-rels"))?;
    let mut genres = tag_names(&d["genres"], 5);
    if genres.is_empty() {
        genres = tag_names(&d["tags"], 5);
    }
    let wiki = wikidata_id(&d["relations"]).and_then(|q| wikipedia(&a, &q));
    let kind = d["type"].as_str().unwrap_or("");
    Some(json!({
        "mbid": id,
        "name": s(&d["name"]),
        "type": artist_type_pt(kind),
        "person": kind == "Person",
        "disambiguation": s(&d["disambiguation"]),
        "country": s(&d["area"]["name"]),
        "beginArea": s(&d["begin-area"]["name"]),
        "begin": s(&d["life-span"]["begin"]),
        "end": s(&d["life-span"]["end"]),
        "ended": d["life-span"]["ended"].as_bool().unwrap_or(false),
        "genres": genres,
        "wiki": wiki,
        "source": "MusicBrainz",
        "link": format!("https://musicbrainz.org/artist/{id}"),
    }))
}

/// Album facts: release date, label, catalog number, type, genres, Wikipedia text.
pub fn fetch_album(title: &str, artist: &str, mbid: Option<&str>) -> Option<Value> {
    let a = agent();
    let id = match mbid {
        Some(id) => id.to_owned(),
        None => {
            let q = format!("release:{} AND artist:{}", phrase(title), phrase(artist));
            let r = mb(&a, &format!("release/?query={}&limit=8", enc(&q)))?;
            let hits = r["releases"].as_array()?;
            // Prefer an official release with the exact title.
            let w = norm(title);
            hits.iter()
                .filter(|h| norm(h["title"].as_str().unwrap_or("")) == w)
                .max_by_key(|h| (h["status"] == "Official") as i64 * 1000 + h["score"].as_i64().unwrap_or(0))
                .or_else(|| hits.first().filter(|h| h["score"].as_i64().unwrap_or(0) >= 95))
                .and_then(|h| s(&h["id"]))?
        }
    };
    let d = mb(&a, &format!("release/{id}?inc=labels+release-groups+genres+tags+url-rels+media"))?;
    let rg = &d["release-group"];
    let mut genres = tag_names(&d["genres"], 5);
    if genres.is_empty() {
        genres = tag_names(&rg["genres"], 5);
    }
    if genres.is_empty() {
        genres = tag_names(&d["tags"], 5);
    }
    let rg_id = s(&rg["id"]);
    let wiki = match wikidata_id(&d["relations"]) {
        Some(q) => wikipedia(&a, &q),
        None => rg_id
            .as_ref()
            .and_then(|g| mb(&a, &format!("release-group/{g}?inc=url-rels")))
            .and_then(|g| wikidata_id(&g["relations"]))
            .and_then(|q| wikipedia(&a, &q)),
    };
    let label = d["label-info"].as_array().and_then(|l| l.first()).cloned().unwrap_or(Value::Null);
    let kind = match rg["primary-type"].as_str().unwrap_or("") {
        "Album" => "Álbum",
        "Single" => "Single",
        "EP" => "EP",
        "Broadcast" => "Transmissão",
        _ => "",
    };
    let secondary: Vec<&str> = rg["secondary-types"]
        .as_array()
        .map(|v| {
            v.iter()
                .filter_map(|x| match x.as_str()? {
                    "Live" => Some("Ao vivo"),
                    "Compilation" => Some("Coletânea"),
                    "Soundtrack" => Some("Trilha sonora"),
                    "Remix" => Some("Remixes"),
                    "Demo" => Some("Demo"),
                    _ => None,
                })
                .collect()
        })
        .unwrap_or_default();
    let media: Vec<String> = d["media"].as_array().map(|m| m.iter().filter_map(|x| s(&x["format"])).collect()).unwrap_or_default();
    Some(json!({
        "mbid": id,
        "title": s(&d["title"]),
        "date": s(&d["date"]),
        "firstDate": s(&rg["first-release-date"]),
        "country": s(&d["country"]),
        "label": s(&label["label"]["name"]),
        "catalog": s(&label["catalog-number"]),
        "barcode": s(&d["barcode"]),
        "type": kind,
        "secondary": secondary,
        "media": media,
        "genres": genres,
        "wiki": wiki,
        "source": "MusicBrainz",
        "link": format!("https://musicbrainz.org/release/{id}"),
    }))
}

/// pt-BR label for a MusicBrainz artist relation on a recording or work.
fn relation_role(r: &Value) -> Option<String> {
    let attrs: Vec<String> = r["attributes"].as_array().map(|a| a.iter().filter_map(s).collect()).unwrap_or_default();
    let ty = r["type"].as_str()?;
    Some(match ty {
        "vocal" => {
            if attrs.iter().any(|a| a.contains("background")) {
                "Backing vocal".into()
            } else if attrs.iter().any(|a| a.contains("guest")) {
                "Voz convidada".into()
            } else {
                "Voz".into()
            }
        }
        "instrument" => attrs.iter().filter(|a| !matches!(a.as_str(), "guest" | "additional")).map(|a| instrument_pt(a)).collect::<Vec<_>>().join(", "),
        "performer" => "Intérprete".into(),
        "producer" => if attrs.iter().any(|a| a == "executive") { "Produção executiva".into() } else { "Produção".into() },
        "co-producer" => "Coprodução".into(),
        "engineer" | "recording" | "audio" | "sound" => "Engenharia de som".into(),
        "mix" => "Mixagem".into(),
        "mastering" => "Masterização".into(),
        "remixer" => "Remix".into(),
        "programming" => "Programação".into(),
        "arranger" | "instrument arranger" | "vocal arranger" | "orchestrator" => "Arranjo".into(),
        "conductor" => "Regência".into(),
        "composer" => "Composição".into(),
        "lyricist" => "Letra".into(),
        "writer" => "Autoria".into(),
        "librettist" => "Libreto".into(),
        "orchestra" => "Orquestra".into(),
        "chorus master" => "Regência do coro".into(),
        _ => return None,
    })
    .filter(|x: &String| !x.is_empty())
}

/// Credits for one song: performers and roles from the recording, writers
/// from its work, samples ("Sampled artist" in the reference).
pub fn fetch_recording(title: &str, artist: &str, album: Option<&str>, duration_ms: i64, mbid: Option<&str>) -> Option<Value> {
    let a = agent();
    let id = match mbid {
        Some(id) => id.to_owned(),
        None => {
            let mut q = format!("recording:{} AND artist:{}", phrase(title), phrase(&split_artists(artist).0));
            if let Some(al) = album.filter(|x| !x.is_empty()) {
                q.push_str(&format!(" AND release:{}", phrase(al)));
            }
            let mut r = mb(&a, &format!("recording/?query={}&limit=10", enc(&q)))?;
            if r["recordings"].as_array().map_or(true, |x| x.is_empty()) && album.is_some() {
                let q = format!("recording:{} AND artist:{}", phrase(title), phrase(&split_artists(artist).0));
                r = mb(&a, &format!("recording/?query={}&limit=10", enc(&q)))?;
            }
            let hits = r["recordings"].as_array()?;
            let w = norm(title);
            hits.iter()
                .filter(|h| norm(h["title"].as_str().unwrap_or("")) == w)
                .min_by_key(|h| {
                    let len = h["length"].as_i64().unwrap_or(0);
                    if duration_ms > 0 && len > 0 { (len - duration_ms).abs() } else { 600_000 }
                })
                .or_else(|| hits.first().filter(|h| h["score"].as_i64().unwrap_or(0) >= 95))
                .and_then(|h| s(&h["id"]))?
        }
    };
    let d = mb(&a, &format!("recording/{id}?inc=artist-credits+artist-rels+work-rels+work-level-rels+recording-rels+isrcs+genres+tags"))?;
    let mut credits: Vec<Value> = vec![];
    let mut push = |name: String, role: String, mbid: Option<String>| {
        if let Some(c) = credits.iter_mut().find(|c| c["name"] == name.as_str()) {
            // Same person, several jobs: "Voz, Produção".
            let roles = c["role"].as_str().unwrap_or("").to_owned();
            if !roles.split(", ").any(|r| r == role) {
                c["role"] = format!("{roles}, {role}").into();
            }
        } else {
            credits.push(json!({ "name": name, "role": role, "mbid": mbid, "source": "musicbrainz" }));
        }
    };
    for (i, c) in d["artist-credit"].as_array().cloned().unwrap_or_default().iter().enumerate() {
        if let Some(n) = s(&c["name"]).or_else(|| s(&c["artist"]["name"])) {
            push(n, if i == 0 { "Artista".into() } else { "Participação".into() }, s(&c["artist"]["id"]));
        }
    }
    let rels = d["relations"].as_array().cloned().unwrap_or_default();
    let mut samples = vec![];
    for r in &rels {
        match r["target-type"].as_str() {
            Some("artist") => {
                if let (Some(n), Some(role)) = (s(&r["artist"]["name"]), relation_role(r)) {
                    push(n, role, s(&r["artist"]["id"]));
                }
            }
            Some("work") => {
                for wr in r["work"]["relations"].as_array().cloned().unwrap_or_default() {
                    if wr["target-type"] == "artist" {
                        if let (Some(n), Some(role)) = (s(&wr["artist"]["name"]), relation_role(&wr)) {
                            push(n, role, s(&wr["artist"]["id"]));
                        }
                    }
                }
            }
            Some("recording") if r["type"] == "samples material" && r["direction"] == "forward" => {
                let rec = &r["recording"];
                let who = rec["artist-credit"].as_array().and_then(|x| x.first()).and_then(|x| s(&x["name"]));
                samples.push(json!({ "title": s(&rec["title"]), "artist": who }));
            }
            _ => {}
        }
    }
    for smp in &samples {
        if let Some(n) = s(&smp["artist"]) {
            push(n, "Artista sampleado".into(), None);
        }
    }
    let mut genres = tag_names(&d["genres"], 4);
    if genres.is_empty() {
        genres = tag_names(&d["tags"], 4);
    }
    let isrc = d["isrcs"].as_array().and_then(|x| x.first()).and_then(s);
    Some(json!({
        "mbid": id,
        "title": s(&d["title"]),
        "credits": credits,
        "samples": samples,
        "genres": genres,
        "isrc": isrc,
        "firstDate": s(&d["first-release-date"]),
        "source": "MusicBrainz",
        "link": format!("https://musicbrainz.org/recording/{id}"),
    }))
}

/// Online info with a cache in `kv` (`info:<kind>:<key>` → {at, data}).
/// Returns (data or null, came from cache).
pub fn cached_or_fetch(db: &Db, kind: &str, key: &str, now: i64, force: bool, fetch: impl FnOnce() -> Option<Value>) -> Value {
    let k = format!("info:{kind}:{}", norm(key));
    if !force {
        if let Some(v) = db.get_kv(&k).ok().flatten().and_then(|s| serde_json::from_str::<Value>(&s).ok()) {
            let at = v["at"].as_i64().unwrap_or(0);
            let fresh = if v["data"].is_null() { MISS_SECS } else { FRESH_SECS };
            if now - at < fresh {
                return v["data"].clone();
            }
        }
    }
    let data = fetch().unwrap_or(Value::Null);
    let _ = db.set_kv(&k, &json!({ "at": now, "data": data }).to_string());
    data
}

/// Download an artist photo once into the cover cache; returns its file path.
pub fn cache_image(url: &str, dir: &Path) -> Option<String> {
    let name = format!("web-{}.img", &blake3::hash(url.as_bytes()).to_hex()[..24]);
    let path = dir.join(name);
    if path.exists() {
        return Some(path.to_string_lossy().into_owned());
    }
    let resp = agent().get(url).call().ok()?;
    let mut bytes = vec![];
    use std::io::Read;
    resp.into_reader().take(8 << 20).read_to_end(&mut bytes).ok()?;
    std::fs::create_dir_all(dir).ok()?;
    std::fs::write(&path, bytes).ok()?;
    Some(path.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_featured_artists() {
        let (m, g) = split_artists("Kanye West feat. André 3000 & Nelly");
        assert_eq!(m, "Kanye West");
        assert_eq!(g, vec!["André 3000", "Nelly"]);
        assert_eq!(split_artists("Caetano Veloso").1.len(), 0);
    }

    #[test]
    fn maps_roles() {
        let r = json!({ "type": "vocal", "attributes": ["background vocals"] });
        assert_eq!(relation_role(&r).unwrap(), "Backing vocal");
        let r = json!({ "type": "instrument", "attributes": ["acoustic guitar"] });
        assert_eq!(relation_role(&r).unwrap(), "Violão");
        assert!(relation_role(&json!({ "type": "misc" })).is_none());
    }

    #[test]
    fn escapes_search_phrases() {
        assert_eq!(phrase("AC/DC: Live!"), "\"AC\\/DC\\: Live\\!\"");
        assert_eq!(enc("a b/ç"), "a%20b%2F%C3%A7");
    }
}
