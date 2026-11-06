//! Free, legally downloadable music: Jamendo (Creative Commons, needs a free
//! client id from devportal.jamendo.com) and the Internet Archive (only items
//! under a Creative Commons or public-domain licence are returned).
//!
//! Base URLs can be overridden (`ARARA_JAMENDO_BASE`, `ARARA_IA_BASE`) for tests.

use serde::Serialize;
use serde_json::Value;
use std::time::Duration;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct FreeTrack {
    /// "jamendo:123" / "ia:identifier/file.mp3"
    pub id: String,
    pub source: &'static str,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration_ms: u64,
    /// Plays directly.
    pub stream_url: String,
    /// Empty when the artist doesn't allow downloads.
    pub download_url: String,
    pub ext: String,
    pub cover_url: String,
    pub license: String,
    pub page_url: String,
}

pub struct FreeMusic {
    agent: ureq::Agent,
    jamendo_base: String,
    ia_base: String,
}

impl Default for FreeMusic {
    fn default() -> Self {
        Self {
            agent: ureq::AgentBuilder::new()
                .timeout(Duration::from_secs(12))
                .user_agent(concat!("Arara Music/", env!("CARGO_PKG_VERSION"), " (https://github.com/Githyot/arara-music)"))
                .build(),
            jamendo_base: std::env::var("ARARA_JAMENDO_BASE").unwrap_or_else(|_| "https://api.jamendo.com/v3.0".into()),
            ia_base: std::env::var("ARARA_IA_BASE").unwrap_or_else(|_| "https://archive.org".into()),
        }
    }
}

fn s(v: &Value, k: &str) -> String {
    match &v[k] {
        Value::String(x) => x.trim().to_string(),
        Value::Array(a) => a.first().and_then(|x| x.as_str()).unwrap_or("").trim().to_string(),
        Value::Number(n) => n.to_string(),
        _ => String::new(),
    }
}

/// "3:25", "205.4" → milliseconds
fn parse_length(l: &str) -> u64 {
    let parts: Vec<f64> = l.split(':').filter_map(|p| p.trim().parse().ok()).collect();
    let secs = parts.iter().fold(0.0, |acc, p| acc * 60.0 + p);
    (secs * 1000.0) as u64
}

fn license_name(url: &str) -> String {
    let u = url.to_lowercase();
    if u.contains("publicdomain") || u.contains("/zero/") {
        return "Domínio público".into();
    }
    // https://creativecommons.org/licenses/by-nc-sa/3.0/ → "CC BY-NC-SA 3.0"
    let parts: Vec<&str> = u.split('/').filter(|p| !p.is_empty()).collect();
    match parts.iter().position(|p| *p == "licenses") {
        Some(i) if i + 1 < parts.len() => {
            let kind = parts[i + 1].to_uppercase();
            let ver = parts.get(i + 2).copied().unwrap_or("");
            format!("CC {kind} {ver}").trim().to_string()
        }
        _ => "Creative Commons".into(),
    }
}

impl FreeMusic {
    /// Both sources; a source that fails is skipped and its error returned alongside.
    pub fn search(&self, query: &str, jamendo_client_id: Option<&str>) -> (Vec<FreeTrack>, Vec<String>) {
        let (mut out, mut errors) = (Vec::new(), Vec::new());
        let (j, ia) = std::thread::scope(|sc| {
            let j = sc.spawn(|| jamendo_client_id.filter(|c| !c.is_empty()).map(|c| self.jamendo(query, c)));
            let ia = sc.spawn(|| self.internet_archive(query));
            (j.join().unwrap_or(None), ia.join().unwrap_or_else(|_| Err("erro interno".into())))
        });
        match j {
            Some(Ok(v)) => out.extend(v),
            Some(Err(e)) => errors.push(format!("Jamendo: {e}")),
            None => {}
        }
        match ia {
            Ok(v) => out.extend(v),
            Err(e) => errors.push(format!("Internet Archive: {e}")),
        }
        (out, errors)
    }

    fn get_json(&self, url: &str, query: &[(&str, &str)]) -> Result<Value, String> {
        let mut req = self.agent.get(url);
        for (k, v) in query {
            req = req.query(k, v);
        }
        req.call()
            .map_err(|e| match e {
                ureq::Error::Status(c, _) => format!("o servidor respondeu {c}"),
                e => format!("sem conexão ({e})"),
            })?
            .into_json::<Value>()
            .map_err(|e| format!("resposta inválida ({e})"))
    }

    pub fn jamendo(&self, query: &str, client_id: &str) -> Result<Vec<FreeTrack>, String> {
        let v = self.get_json(
            &format!("{}/tracks/", self.jamendo_base),
            &[("client_id", client_id), ("format", "json"), ("limit", "30"), ("search", query), ("audioformat", "mp32"), ("include", "licenses")],
        )?;
        if v["headers"]["status"].as_str() == Some("failed") {
            return Err(s(&v["headers"], "error_message"));
        }
        Ok(v["results"]
            .as_array()
            .map(|a| a.as_slice())
            .unwrap_or_default()
            .iter()
            .filter(|t| !s(t, "audio").is_empty())
            .map(|t| {
                let allowed = t["audiodownload_allowed"].as_bool().unwrap_or(true);
                FreeTrack {
                    id: format!("jamendo:{}", s(t, "id")),
                    source: "Jamendo",
                    title: s(t, "name"),
                    artist: s(t, "artist_name"),
                    album: s(t, "album_name"),
                    duration_ms: t["duration"].as_u64().unwrap_or(0) * 1000,
                    stream_url: s(t, "audio"),
                    download_url: if allowed { s(t, "audiodownload") } else { String::new() },
                    ext: "mp3".into(),
                    cover_url: s(t, "image"),
                    license: license_name(&s(t, "license_ccurl")),
                    page_url: s(t, "shareurl"),
                }
            })
            .collect())
    }

    /// Search audio items with an open licence, then list the playable files of the first few.
    pub fn internet_archive(&self, query: &str) -> Result<Vec<FreeTrack>, String> {
        let q = format!(
            "({}) AND mediatype:(audio) AND (licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)",
            query.replace(['(', ')', ':'], " ")
        );
        let v = self.get_json(
            &format!("{}/advancedsearch.php", self.ia_base),
            &[("q", &q), ("fl[]", "identifier"), ("fl[]", "title"), ("fl[]", "creator"), ("fl[]", "licenseurl"), ("rows", "8"), ("output", "json")],
        )?;
        let docs: Vec<Value> = v["response"]["docs"].as_array().cloned().unwrap_or_default();
        let items: Vec<Vec<FreeTrack>> = std::thread::scope(|sc| {
            let hs: Vec<_> = docs.iter().map(|d| sc.spawn(move || self.ia_item(d).unwrap_or_default())).collect();
            hs.into_iter().map(|h| h.join().unwrap_or_default()).collect()
        });
        Ok(items.into_iter().flatten().collect())
    }

    fn ia_item(&self, doc: &Value) -> Result<Vec<FreeTrack>, String> {
        let id = s(doc, "identifier");
        if id.is_empty() {
            return Ok(vec![]);
        }
        let meta = self.get_json(&format!("{}/metadata/{}", self.ia_base, id), &[])?;
        let license_url = s(&meta["metadata"], "licenseurl");
        if !(license_url.contains("creativecommons.org") || license_url.contains("publicdomain")) {
            return Ok(vec![]); // never offer something without an open licence
        }
        let album = s(&meta["metadata"], "title");
        let creator = s(&meta["metadata"], "creator");
        let files = meta["files"].as_array().cloned().unwrap_or_default();
        // Prefer MP3 (smaller, plays everywhere); fall back to FLAC/OGG.
        let pick = |fmt: &[&str]| -> Vec<&Value> {
            files.iter().filter(|f| fmt.iter().any(|x| s(f, "format").eq_ignore_ascii_case(x))).collect()
        };
        let mut chosen = pick(&["VBR MP3", "MP3", "128Kbps MP3", "64Kbps MP3"]);
        if chosen.is_empty() {
            chosen = pick(&["Flac", "Ogg Vorbis"]);
        }
        Ok(chosen
            .into_iter()
            .take(40)
            .map(|f| {
                let name = s(f, "name");
                let ext = name.rsplit('.').next().unwrap_or("mp3").to_lowercase();
                let url = format!("{}/download/{}/{}", self.ia_base, id, urlencode_path(&name));
                let title = Some(s(f, "title")).filter(|t| !t.is_empty()).unwrap_or_else(|| {
                    name.rsplit('/').next().unwrap_or(&name).rsplit_once('.').map(|x| x.0.to_string()).unwrap_or(name.clone())
                });
                FreeTrack {
                    id: format!("ia:{id}/{name}"),
                    source: "Internet Archive",
                    title,
                    artist: Some(s(f, "creator")).filter(|c| !c.is_empty()).unwrap_or_else(|| creator.clone()),
                    album: Some(s(f, "album")).filter(|c| !c.is_empty()).unwrap_or_else(|| album.clone()),
                    duration_ms: parse_length(&s(f, "length")),
                    stream_url: url.clone(),
                    download_url: url,
                    ext,
                    cover_url: format!("{}/services/img/{}", self.ia_base, id),
                    license: license_name(&license_url),
                    page_url: format!("{}/details/{}", self.ia_base, id),
                }
            })
            .collect())
    }
}

fn urlencode_path(p: &str) -> String {
    p.split('/')
        .map(|seg| {
            seg.bytes()
                .map(|b| match b {
                    b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
                    _ => format!("%{b:02X}"),
                })
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn helpers() {
        assert_eq!(parse_length("3:25"), 205_000);
        assert_eq!(parse_length("205.5"), 205_500);
        assert_eq!(license_name("https://creativecommons.org/licenses/by-nc-sa/3.0/"), "CC BY-NC-SA 3.0");
        assert_eq!(license_name("http://creativecommons.org/publicdomain/zero/1.0/"), "Domínio público");
        assert_eq!(urlencode_path("CD 1/01 Canção.mp3"), "CD%201/01%20Can%C3%A7%C3%A3o.mp3");
    }
}
