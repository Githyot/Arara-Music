//! Letras do LRCLIB (lrclib.net): o app busca quando o usuário pede, escolhe
//! o resultado que mais combina com a música e guarda só na biblioteca local.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Result {
    track_name: String,
    artist_name: String,
    instrumental: bool,
    plain_lyrics: Option<String>,
    synced_lyrics: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Line {
    /// Segundos desde o começo da música.
    pub t: f64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Default)]
pub struct Lyrics {
    pub found: bool,
    pub instrumental: bool,
    pub plain: String,
    pub synced: Vec<Line>,
}

/// Escolhe, entre os resultados da busca (JSON do `/api/search`), o que tem o
/// mesmo título e artista; empate vai para quem tem letra sincronizada.
pub fn pick(results_json: &str, title: &str, artist: &str) -> Lyrics {
    let results: Vec<Result> = serde_json::from_str(results_json).unwrap_or_default();
    let (t, a) = (norm(title), norm(artist));
    let best = results
        .iter()
        .filter(|r| {
            r.instrumental
                || r.plain_lyrics
                    .as_deref()
                    .is_some_and(|p| !p.trim().is_empty())
        })
        .max_by_key(|r| {
            let rt = norm(&r.track_name);
            let ra = norm(&r.artist_name);
            let mut score = 0;
            if rt == t {
                score += 4;
            } else if rt.contains(&t) || t.contains(&rt) {
                score += 2;
            }
            if !a.is_empty() && (ra == a || ra.contains(&a) || a.contains(&ra)) {
                score += 3;
            }
            if r.synced_lyrics.as_deref().is_some_and(|s| !s.is_empty()) {
                score += 1;
            }
            score
        });
    match best {
        None => Lyrics::default(),
        Some(r) => {
            let synced = parse_lrc(r.synced_lyrics.as_deref().unwrap_or(""));
            let plain = r.plain_lyrics.clone().unwrap_or_else(|| {
                synced
                    .iter()
                    .map(|l| l.text.as_str())
                    .collect::<Vec<_>>()
                    .join("\n")
            });
            Lyrics {
                found: true,
                instrumental: r.instrumental,
                plain: plain.trim().to_string(),
                synced,
            }
        }
    }
}

pub fn pick_json(results_json: &str, title: &str, artist: &str) -> String {
    serde_json::to_string(&pick(results_json, title, artist)).unwrap_or_else(|_| "{}".into())
}

/// "[01:02.50] texto" -> (62.5, "texto"). Linhas sem tempo ficam de fora.
pub fn parse_lrc(text: &str) -> Vec<Line> {
    let mut out = Vec::new();
    for raw in text.lines() {
        let mut rest = raw.trim();
        let mut times = Vec::new();
        while let Some(r) = rest.strip_prefix('[') {
            let Some(end) = r.find(']') else { break };
            let Some(t) = parse_time(&r[..end]) else {
                break;
            };
            times.push(t);
            rest = r[end + 1..].trim_start();
        }
        for t in times {
            out.push(Line {
                t,
                text: rest.to_string(),
            });
        }
    }
    out.sort_by(|a, b| a.t.total_cmp(&b.t));
    out
}

fn parse_time(s: &str) -> Option<f64> {
    let (m, sec) = s.split_once(':')?;
    let m: f64 = m.trim().parse().ok()?;
    let sec: f64 = sec.trim().parse().ok()?;
    Some(m * 60.0 + sec)
}

/// Minúsculas, sem acento e sem pontuação, para comparar nomes.
pub fn norm(s: &str) -> String {
    s.to_lowercase()
        .chars()
        .filter_map(crate::library::fold_accent)
        .filter(|c| c.is_alphanumeric() || *c == ' ')
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_lrc() {
        let l = parse_lrc("[ar: x]\n[00:01.50] Primeira\n[01:02.00][02:00.00] Volta\nsem tempo");
        assert_eq!(l.len(), 3);
        assert_eq!(
            l[0],
            Line {
                t: 1.5,
                text: "Primeira".into()
            }
        );
        assert_eq!(l[1].t, 62.0);
        assert_eq!(l[2].text, "Volta");
    }

    #[test]
    fn picks_the_matching_song() {
        let json = r#"[
            {"trackName":"Outra","artistName":"Fulano","plainLyrics":"nao"},
            {"trackName":"Canção Teste","artistName":"Banda","plainLyrics":"la la","syncedLyrics":"[00:02.00] la la"},
            {"trackName":"Canção Teste (Ao Vivo)","artistName":"Banda","plainLyrics":"ao vivo"}
        ]"#;
        let l = pick(json, "Cancao teste", "banda");
        assert!(l.found);
        assert_eq!(l.plain, "la la");
        assert_eq!(l.synced.len(), 1);
        assert!(!pick("[]", "x", "y").found);
    }
}
