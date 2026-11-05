//! "Natural" ordering for names: case-insensitive, accents folded, and runs of
//! digits compared as numbers — "Artista 2" < "Artista 10", "Álbum" ≈ "album".
//! Registered in SQLite as `COLLATE NATSORT`.

use std::cmp::Ordering;

fn fold(c: char) -> char {
    let c = c.to_lowercase().next().unwrap_or(c);
    match c {
        'á' | 'à' | 'â' | 'ã' | 'ä' | 'å' => 'a',
        'é' | 'è' | 'ê' | 'ë' => 'e',
        'í' | 'ì' | 'î' | 'ï' => 'i',
        'ó' | 'ò' | 'ô' | 'õ' | 'ö' => 'o',
        'ú' | 'ù' | 'û' | 'ü' => 'u',
        'ç' => 'c',
        'ñ' => 'n',
        _ => c,
    }
}

pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let mut x = a.chars().peekable();
    let mut y = b.chars().peekable();
    loop {
        match (x.peek().copied(), y.peek().copied()) {
            (None, None) => return a.cmp(b), // equal when folded: fall back to a stable order
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(c1), Some(c2)) if c1.is_ascii_digit() && c2.is_ascii_digit() => {
                let mut n1 = String::new();
                while let Some(c) = x.peek().copied().filter(|c| c.is_ascii_digit()) {
                    n1.push(c);
                    x.next();
                }
                let mut n2 = String::new();
                while let Some(c) = y.peek().copied().filter(|c| c.is_ascii_digit()) {
                    n2.push(c);
                    y.next();
                }
                let t1 = n1.trim_start_matches('0');
                let t2 = n2.trim_start_matches('0');
                let ord = t1.len().cmp(&t2.len()).then_with(|| t1.cmp(t2));
                if ord != Ordering::Equal {
                    return ord;
                }
            }
            (Some(c1), Some(c2)) => {
                let ord = fold(c1).cmp(&fold(c2));
                if ord != Ordering::Equal {
                    return ord;
                }
                x.next();
                y.next();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn orders_naturally() {
        let mut v = vec!["Artista 10", "artista 2", "Álbum", "album 01", "Zé", "Artista 1", "Beta"];
        v.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(v, vec!["Álbum", "album 01", "Artista 1", "artista 2", "Artista 10", "Beta", "Zé"]);
    }
}
