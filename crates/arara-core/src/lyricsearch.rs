//! Searching songs by their words: "I forgot the name but I remember the lyrics".
//!
//! Every saved lyric (table `lyrics`) is copied, without timestamps, into the
//! full-text table `lyrics_fts` (rowid = track id). The search bar matches it
//! together with title/artist/album, and `letra:"…"` searches only the words.
//! Each lyric hit shows the line that matched (see [`snippet`]).

use rusqlite::params;
use std::collections::{HashMap, HashSet};

use crate::db::Db;
use crate::Result;

/// The words of a song, one line per sung line (timestamps, tags and duet
/// markers removed). Synced lyrics win over plain ones.
pub fn words_of(synced: Option<&str>, plain: Option<&str>) -> String {
    let from_synced = synced
        .filter(|s| !s.trim().is_empty())
        .map(|s| crate::lyrics::parse_lrc(s, None).into_iter().map(|l| l.text).collect::<Vec<_>>().join("\n"))
        .filter(|s| !s.trim().is_empty());
    let text = from_synced.or_else(|| plain.map(str::to_owned)).unwrap_or_default();
    let mut out: Vec<&str> = Vec::new();
    for l in text.lines().map(str::trim).filter(|l| !l.is_empty()) {
        // Drop a stray LRC metadata line ([ar:…]) left in "plain" lyrics.
        if l.starts_with('[') && l.ends_with(']') {
            continue;
        }
        out.push(l);
    }
    out.join("\n")
}

/// Lowercase, without accents ("Coração" → "coracao"), like the FTS tokenizer.
pub fn fold(s: &str) -> String {
    use unicode_normalization::UnicodeNormalization;
    s.nfd().filter(|c| !unicode_normalization::char::is_combining_mark(*c)).collect::<String>().to_lowercase()
}

/// Query words, folded, punctuation dropped ("Don't stop" → ["don", "t", "stop"]
/// like the tokenizer splits it).
pub fn query_words(q: &str) -> Vec<String> {
    fold(q)
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(str::to_owned)
        .collect()
}

/// FTS5 MATCH expression: every word, each as a prefix ("amo" finds "amor").
pub fn fts_query(words: &[String]) -> String {
    words.iter().map(|w| format!("\"{w}\"*")).collect::<Vec<_>>().join(" ")
}

/// Free text this short would match the words of almost every song.
pub fn long_enough(words: &[String]) -> bool {
    words.iter().map(|w| w.chars().count()).sum::<usize>() >= 3
}

/// Byte spans of the words of `line` that start with one of `words`
/// (folded comparison), plus a score: distinct query words found, and a
/// bonus when they appear in the order typed, next to each other.
fn hits(line: &str, words: &[String]) -> (usize, Vec<(usize, usize)>) {
    // Words of the line with their byte range in the original text.
    let mut toks: Vec<(usize, usize, String)> = Vec::new();
    let mut start: Option<usize> = None;
    for (i, c) in line.char_indices().chain(std::iter::once((line.len(), ' '))) {
        if c.is_alphanumeric() {
            start.get_or_insert(i);
        } else if let Some(s) = start.take() {
            toks.push((s, i, fold(&line[s..i])));
        }
    }
    let mut found: HashSet<usize> = HashSet::new();
    let mut spans = Vec::new();
    let mut matched_at: Vec<Option<usize>> = vec![None; toks.len()];
    for (ti, (s, e, f)) in toks.iter().enumerate() {
        if let Some(qi) = words.iter().position(|w| f.starts_with(w.as_str())) {
            found.insert(qi);
            spans.push((*s, *e));
            matched_at[ti] = Some(qi);
        }
    }
    // Longest run of consecutive line words matching consecutive query words.
    let mut best_run = 0;
    for ti in 0..toks.len() {
        let mut run = 0;
        while ti + run < toks.len() && run < words.len() && toks[ti + run].2.starts_with(words[run].as_str()) {
            run += 1;
        }
        best_run = best_run.max(run);
        if run == 0 {
            // Also count a run that starts in the middle of the phrase typed.
            if let Some(q0) = matched_at[ti] {
                let mut r = 0;
                while ti + r < toks.len() && q0 + r < words.len() && toks[ti + r].2.starts_with(words[q0 + r].as_str()) {
                    r += 1;
                }
                best_run = best_run.max(r);
            }
        }
    }
    (found.len() * 10 + best_run, spans)
}

fn escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

/// The line of `text` that best matches `words`, as Qt StyledText with the
/// matched words in bold. A long line starts a little before the first hit
/// so the hit stays visible. None when no line has any of the words.
pub fn snippet(text: &str, words: &[String]) -> Option<String> {
    let lines: Vec<&str> = text.lines().collect();
    // A line alone, or joined with the next one when the words cross a line
    // break ("…eu sei / que vou te amar"); a pair must score clearly higher.
    let mut best: Option<(usize, String)> = None;
    for (i, l) in lines.iter().enumerate() {
        let mut cands = vec![(hits(l, words).0, l.to_string())];
        if let Some(next) = lines.get(i + 1) {
            let joined = format!("{l} / {next}");
            let s = hits(&joined, words).0;
            if s >= cands[0].0.max(hits(next, words).0) + 10 {
                cands.push((s, joined));
            }
        }
        for (score, text) in cands {
            if score > 0 && best.as_ref().map(|(b, _)| score > *b).unwrap_or(true) {
                best = Some((score, text));
            }
        }
    }
    let (_, line) = best?;
    let (_, spans) = hits(&line, words);
    // Keep about 28 characters before the first hit.
    let first = spans.first().map(|s| s.0).unwrap_or(0);
    let mut cut = 0;
    let mut prefix = "";
    if line[..first].chars().count() > 28 {
        let back: usize = line[..first].char_indices().rev().nth(27).map(|(b, _)| b).unwrap_or(0);
        // Start at a word boundary.
        cut = line[back..first].find(' ').map(|p| back + p + 1).unwrap_or(back);
        prefix = "…";
    }
    let mut out = String::from(prefix);
    let mut pos = cut;
    for (s, e) in spans.into_iter().filter(|(s, _)| *s >= cut) {
        out.push_str(&escape(&line[pos..s]));
        out.push_str("<b>");
        out.push_str(&escape(&line[s..e]));
        out.push_str("</b>");
        pos = e;
    }
    out.push_str(&escape(&line[pos..]));
    Some(out)
}

impl Db {
    /// Keep the search copy of one song's lyrics up to date.
    pub fn index_lyrics(&self, track_id: i64, synced: Option<&str>, plain: Option<&str>) -> Result<()> {
        self.conn.execute("DELETE FROM lyrics_fts WHERE rowid = ?1", [track_id])?;
        let words = words_of(synced, plain);
        if !words.is_empty() {
            self.conn.execute("INSERT INTO lyrics_fts(rowid, words) VALUES (?1, ?2)", params![track_id, words])?;
        }
        Ok(())
    }

    /// Forget a song's lyrics (and their search copy).
    pub fn delete_lyrics(&self, track_id: i64) -> Result<()> {
        self.conn.execute("DELETE FROM lyrics WHERE track_id = ?1", [track_id])?;
        self.conn.execute("DELETE FROM lyrics_fts WHERE rowid = ?1", [track_id])?;
        Ok(())
    }

    /// Index lyrics saved before 0.7.45 (or by an older copy of the app) and
    /// drop the copies of deleted songs. Cheap when there's nothing to do;
    /// runs in the background after the window shows. Returns songs indexed.
    pub fn index_lyrics_backlog(&self) -> Result<usize> {
        self.conn.execute(
            "DELETE FROM lyrics_fts WHERE rowid NOT IN (SELECT track_id FROM lyrics WHERE synced IS NOT NULL OR plain IS NOT NULL)",
            [],
        )?;
        let todo: Vec<(i64, Option<String>, Option<String>)> = {
            let mut st = self.conn.prepare(
                "SELECT track_id, synced, plain FROM lyrics
                 WHERE (synced IS NOT NULL OR plain IS NOT NULL) AND track_id NOT IN (SELECT rowid FROM lyrics_fts)",
            )?;
            let rows = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?;
            rows.flatten().collect()
        };
        if todo.is_empty() {
            return Ok(0);
        }
        // Small batches: the scanner shares the write lock.
        for chunk in todo.chunks(200) {
            let tx = self.conn.unchecked_transaction()?;
            for (id, s, p) in chunk {
                let words = words_of(s.as_deref(), p.as_deref());
                if !words.is_empty() {
                    tx.execute("INSERT INTO lyrics_fts(rowid, words) VALUES (?1, ?2)", params![id, words])?;
                }
            }
            tx.commit()?;
        }
        Ok(todo.len())
    }

    /// The matching line of each song in `ids` whose lyrics hold `words`.
    pub fn lyric_snippets(&self, ids: &[i64], words: &[String]) -> Result<HashMap<i64, String>> {
        let mut out = HashMap::new();
        if words.is_empty() {
            return Ok(out);
        }
        for chunk in ids.chunks(500) {
            let marks = vec!["?"; chunk.len()].join(",");
            let mut st = self.conn.prepare(&format!("SELECT rowid, words FROM lyrics_fts WHERE rowid IN ({marks})"))?;
            let rows = st.query_map(rusqlite::params_from_iter(chunk.iter()), |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
            for (id, text) in rows.flatten() {
                if let Some(s) = snippet(&text, words) {
                    out.insert(id, s);
                }
            }
        }
        Ok(out)
    }

    /// Ids of the songs whose title, artist or album match `words`.
    pub fn metadata_matches(&self, words: &[String]) -> Result<HashSet<i64>> {
        if words.is_empty() {
            return Ok(HashSet::new());
        }
        let mut st = self.conn.prepare("SELECT rowid FROM tracks_fts WHERE tracks_fts MATCH ?1")?;
        let rows = st.query_map([fts_query(words)], |r| r.get(0))?;
        Ok(rows.flatten().collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn w(q: &str) -> Vec<String> {
        query_words(q)
    }

    #[test]
    fn words_without_timestamps() {
        let s = "[ar:Alguém]\n[00:01.00]Eu sei que vou\n[00:03.00]<00:03.00>Te <00:03.50>amar\n[00:05.00]";
        assert_eq!(words_of(Some(s), None), "Eu sei que vou\nTe amar");
        assert_eq!(words_of(None, Some("  a\n\n b ")), "a\nb");
        assert_eq!(words_of(Some(""), Some("x")), "x");
    }

    #[test]
    fn best_line_with_bold_words() {
        let text = "Tudo bem\nEu sei que vou te amar\nPor toda a minha vida";
        assert_eq!(snippet(text, &w("vou te am")).unwrap(), "Eu sei que <b>vou</b> <b>te</b> <b>amar</b>");
        // Accents and case don't matter.
        assert_eq!(snippet("Meu CORAÇÃO", &w("coracao")).unwrap(), "Meu <b>CORAÇÃO</b>");
        assert!(snippet(text, &w("xyz")).is_none());
    }

    #[test]
    fn phrase_across_two_lines() {
        let text = "Eu sei\nque vou te amar\noutra coisa";
        assert_eq!(snippet(text, &w("sei que vou")).unwrap(), "Eu <b>sei</b> / <b>que</b> <b>vou</b> te amar");
    }

    #[test]
    fn long_line_starts_near_the_hit() {
        let text = "um dois tres quatro cinco seis sete oito nove dez onze doze treze catorze";
        let s = snippet(text, &w("treze")).unwrap();
        assert!(s.starts_with('…'), "{s}");
        assert!(s.contains("<b>treze</b>"));
    }

    #[test]
    fn escapes_markup() {
        assert_eq!(snippet("a <b> & love", &w("love")).unwrap(), "a &lt;b&gt; &amp; <b>love</b>");
    }
}
