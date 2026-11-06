//! "Explicit" (E) marking, like Apple Music's badge.
//!
//! Three sources, in order of trust:
//! 1. what the user chose in the track menu (`tracks.explicit_user`);
//! 2. the file tag or the server (`tracks.explicit`): iTunes `rtng` atom /
//!    `ITUNESADVISORY`, Vorbis `EXPLICIT`, OpenSubsonic `explicitStatus`…;
//! 3. a guess from the lyrics (`tracks.explicit_lyrics`), when the song has
//!    lyrics and contains strong profanity in Portuguese, English or Spanish.
//!
//! The UI shows the badge for 1 and 2 always, and for 3 only when the
//! "detect from lyrics" preference is on.

/// Interpret an advisory tag value. `Some(true)` explicit, `Some(false)` clean,
/// `None` when the value says nothing.
pub fn from_tag_value(v: &str) -> Option<bool> {
    let v = v.trim().to_lowercase();
    match v.as_str() {
        // iTunes: 1 = explicit, 4 = explicit (old), 2 = clean, 0 = none.
        "1" | "4" | "explicit" | "e" | "yes" | "true" | "explícito" | "explicito" => Some(true),
        "2" | "clean" | "edited" | "false" | "no" | "notexplicit" | "not explicit" => Some(false),
        "" | "0" | "none" => None,
        _ if v.contains("explicit") && !v.contains("not") && !v.contains("non") => Some(true),
        _ => None,
    }
}

/// Words that are explicit on their own (matched as whole words).
const WORDS: &[&str] = &[
    // pt
    "caralho", "porra", "buceta", "boceta", "xoxota", "xereca", "piroca", "pica", "rola", "cu", "cuzao",
    "puta", "putas", "puto", "putaria", "putinha", "merda", "bosta", "viado", "arrombado", "arrombada",
    "vagabunda", "vadia", "boquete", "punheta", "siririca", "foda", "fodase", "fodasse", "fdp", "vsf", "pqp",
    "tnc", "corno", "cacete", "safada", "safado", "gozar", "gozei", "gozou", "goza", "chupa",
    "rabuda", "tesão", "tesao", "piranha", "periguete",
    // en
    "shit", "shits", "shitty", "bullshit", "bitch", "bitches", "bitchin", "pussy", "pussies", "cunt", "whore", "whores",
    "hoe", "hoes", "asshole", "assholes", "nigga", "niggas", "nigger", "dick", "dicks", "cock", "cocks", "slut", "sluts",
    "twat", "blowjob", "jizz", "cum", "titties", "tits",
    // es
    "mierda", "pendejo", "pendeja", "coño", "verga", "culo", "cabrón", "cabron", "putita", "perra", "maricón", "maricon",
];

/// Word beginnings that are explicit (fuck…, fod…, fud…).
const STEMS: &[&str] = &[
    "fuck", "motherfuck", "fod", "fud", "fode", "arromb", "putari", "punhet", "chinga", "chingad", "caralh", "porr",
    "bucet", "cuza", "fdp",
];

fn fold(c: char) -> char {
    match c {
        'á' | 'à' | 'â' | 'ã' | 'ä' => 'a',
        'é' | 'è' | 'ê' | 'ë' => 'e',
        'í' | 'ì' | 'î' | 'ï' => 'i',
        'ó' | 'ò' | 'ô' | 'õ' | 'ö' => 'o',
        'ú' | 'ù' | 'û' | 'ü' => 'u',
        'ç' => 'c',
        'ñ' => 'n',
        c => c,
    }
}

fn norm(s: &str) -> String {
    s.chars().flat_map(char::to_lowercase).map(fold).collect()
}

/// Strip LRC timestamps and enhanced word stamps: "[01:02.03]" and "<01:02.03>".
fn strip_stamps(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut depth = 0u32;
    for c in s.chars() {
        match c {
            '[' | '<' => depth += 1,
            ']' | '>' if depth > 0 => {
                depth -= 1;
                out.push(' ');
            }
            _ if depth == 0 => out.push(c),
            _ => {}
        }
    }
    out
}

/// How many explicit words a lyric has.
pub fn count_in_lyrics(text: &str) -> usize {
    let text = norm(&strip_stamps(text));
    let words: std::collections::HashSet<String> = WORDS.iter().map(|w| norm(w)).collect();
    let stems: Vec<String> = STEMS.iter().map(|w| norm(w)).collect();
    let mut n = 0;
    for w in text.split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty()) {
        if words.contains(w) {
            n += 1;
        } else if stems.iter().any(|s| w.starts_with(s.as_str())) && !is_innocent(w) {
            n += 1;
        }
    }
    n
}

fn is_innocent(w: &str) -> bool {
    // "porr…" also starts "porrada"/"porre", and "fud…"/"fod…" English words.
    const INNOCENT: &[&str] = &["porrada", "porradas", "porre", "porres", "porrete", "fodder", "fudge", "fudges"];
    INNOCENT.contains(&w)
}

/// A lyric is considered explicit with at least two hits (one stray word, often
/// a name or a homograph like "pica"/"rola"/"pó", is not enough), or one hit of
/// an unambiguous stem (fuck…, caralh…).
pub fn lyrics_are_explicit(text: &str) -> bool {
    let t = norm(&strip_stamps(text));
    let strong = ["fuck", "caralh", "motherfuck", "bucet", "putari", "punhet", "arromb", "nigga", "pussy", "bitch"];
    let has_strong = t
        .split(|c: char| !c.is_alphanumeric())
        .any(|w| strong.iter().any(|s| w.starts_with(s)));
    has_strong || count_in_lyrics(text) >= 2
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tags() {
        assert_eq!(from_tag_value("1"), Some(true));
        assert_eq!(from_tag_value("4"), Some(true));
        assert_eq!(from_tag_value("2"), Some(false));
        assert_eq!(from_tag_value("0"), None);
        assert_eq!(from_tag_value("Explicit"), Some(true));
        assert_eq!(from_tag_value("clean"), Some(false));
        assert_eq!(from_tag_value("notExplicit"), Some(false));
    }

    #[test]
    fn lyrics() {
        assert!(lyrics_are_explicit("[00:01.00]What the fuck is going on"));
        assert!(lyrics_are_explicit("Vai tomar no cu, sua puta"));
        assert!(lyrics_are_explicit("[00:02.00]<00:02.00>Que <00:02.50>caralho"));
        assert!(!lyrics_are_explicit("Garota de Ipanema, olha que coisa mais linda"));
        assert!(!lyrics_are_explicit("Deu porrada na mesa, tomou um porre"));
        assert!(!lyrics_are_explicit("Here comes the sun, and I say it's all right"));
        // One ambiguous word alone is not enough.
        assert!(!lyrics_are_explicit("A rola de bolinha rolou"));
    }
}
