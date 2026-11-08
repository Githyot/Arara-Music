//! Liga as cifras às músicas do Arara Music: a cifra "combina" com uma faixa
//! quando o título é o mesmo (sem acento, maiúsculas, pontuação e enfeites
//! como "(Remaster 2011)" ou "- Ao Vivo") e o artista também bate. Cifra sem
//! artista combina só pelo título.

use crate::lyrics::norm;
use serde_json::Value;
use std::collections::HashMap;

/// "Tempo Perdido (Remasterizado) - Ao Vivo" -> "tempo perdido".
pub fn clean_title(title: &str) -> String {
    let mut t = String::new();
    let mut depth = 0i32;
    for c in title.chars() {
        match c {
            '(' | '[' | '{' => depth += 1,
            ')' | ']' | '}' => depth = (depth - 1).max(0),
            _ if depth == 0 => t.push(c),
            _ => {}
        }
    }
    let lower = t.to_lowercase();
    // Corta enfeites depois de " - " (versão, ao vivo, remaster, feat.).
    let cut = [" - ", " – ", " feat.", " feat ", " ft. "]
        .iter()
        .filter_map(|sep| lower.find(sep))
        .min();
    let base = match cut {
        Some(i) if i > 0 => &t[..i],
        _ => t.as_str(),
    };
    let n = norm(base);
    if n.is_empty() {
        norm(title)
    } else {
        n
    }
}

/// Primeiro nome de uma lista "A, B & C feat. D".
fn artists(artist: &str) -> Vec<String> {
    let mut s = artist.to_lowercase();
    for sep in [" feat. ", " feat ", " ft. ", " & ", " e ", " x ", ";", "/", ","] {
        s = s.replace(sep, "\u{1}");
    }
    s.split('\u{1}').map(norm).filter(|a| !a.is_empty()).collect()
}

fn artist_matches(sheet: &str, track: &str) -> bool {
    let a = artists(sheet);
    if a.is_empty() {
        return true;
    }
    let b = artists(track);
    a.iter().any(|x| b.iter().any(|y| x == y || x.contains(y.as_str()) || y.contains(x.as_str())))
}

pub struct Index {
    by_title: HashMap<String, Vec<Value>>,
}

impl Index {
    pub fn new(songs: Vec<Value>) -> Self {
        let mut by_title: HashMap<String, Vec<Value>> = HashMap::new();
        for s in songs {
            let t = s.get("title").and_then(Value::as_str).unwrap_or("");
            let key = clean_title(t);
            if !key.is_empty() {
                by_title.entry(key).or_default().push(s);
            }
        }
        Self { by_title }
    }

    /// A cifra da música: primeiro as salvas (com `id`) antes dos exemplos,
    /// depois as que têm o artista preenchido.
    pub fn find(&self, title: &str, artist: &str) -> Option<&Value> {
        let list = self.by_title.get(&clean_title(title))?;
        let artist_of = |v: &Value| v.get("artist").and_then(Value::as_str).unwrap_or("").to_string();
        list.iter()
            .filter(|v| artist_matches(&artist_of(v), artist))
            .max_by_key(|v| (v.get("id").and_then(Value::as_str).is_some(), !artist_of(v).is_empty()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn cleans_titles() {
        assert_eq!(clean_title("Tempo Perdido (Remasterizado)"), "tempo perdido");
        assert_eq!(clean_title("Faroeste Caboclo - Ao Vivo"), "faroeste caboclo");
        assert_eq!(clean_title("Ciúme de Você"), "ciume de voce");
        assert_eq!(clean_title("(Intro)"), "intro");
    }

    #[test]
    fn finds_by_title_and_artist() {
        let ix = Index::new(vec![
            json!({"id":"a","title":"Asa Branca","artist":"Luiz Gonzaga"}),
            json!({"id":"b","title":"Asa Branca","artist":"Outro"}),
            json!({"id":"c","title":"Sem Artista"}),
        ]);
        assert_eq!(ix.find("Asa branca (Ao Vivo)", "Luiz Gonzaga & Dominguinhos").unwrap()["id"], "a");
        assert_eq!(ix.find("Sem artista", "Qualquer").unwrap()["id"], "c");
        assert!(ix.find("Asa Branca", "Ninguém").is_none());
        assert!(ix.find("Outra", "Luiz Gonzaga").is_none());
    }
}
