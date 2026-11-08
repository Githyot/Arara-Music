//! Leitura de cifra colada (texto do jeito que aparece em sites e PDFs).
//!
//! Do texto só saem a estrutura e os acordes: nome de cada parte, quantas
//! vezes repete e a sequência de acordes. Linhas de letra e de tablatura são
//! ignoradas, porque o app guarda a música como acordes por parte.
//!
//! Formatos reconhecidos:
//! - Cabeçalho de parte: `[Refrão]`, `[Intro] (2x)`, `Refrão:` ou
//!   `[Intro] Am G F` (acordes na mesma linha).
//! - Linha de acordes: só acordes, com separadores opcionais (`|`, `-`, `(`, `)`)
//!   e marcas de repetição (`2x`, `x2`, `(2x)`).

use crate::Chord;
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Section {
    pub name: String,
    pub repeat: u32,
    pub chords: Vec<String>,
    /// Tablatura (riff, solo, dedilhado) colada nessa parte, linha por linha.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub tab: String,
    /// Batida usada (índice em `strums` da música), quando o texto diz.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strum: Option<usize>,
}

/// Lê a cifra e devolve as partes com acordes (partes vazias ficam de fora).
pub fn parse(text: &str) -> Vec<Section> {
    let mut sections: Vec<Section> = Vec::new();
    let mut current: Option<Section> = None;

    let flush = |current: &mut Option<Section>, sections: &mut Vec<Section>| {
        if let Some(sec) = current.take() {
            if !sec.chords.is_empty() || !sec.tab.is_empty() {
                sections.push(sec);
            }
        }
    };

    let lines: Vec<&str> = text.lines().collect();
    for (idx, raw) in lines.iter().enumerate() {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }

        if let Some((name, rest)) = header(line) {
            flush(&mut current, &mut sections);
            let mut sec = Section {
                name,
                repeat: 1,
                chords: Vec::new(),
                tab: String::new(),
                strum: None,
            };
            if let Some(line) = chord_line(rest) {
                sec.chords.extend(line.chords);
                sec.repeat = sec.repeat.max(line.repeat);
            } else if let Some(r) = repeat_mark(rest.trim()) {
                sec.repeat = r;
            }
            current = Some(sec);
            continue;
        }

        let prev_is_tab = idx > 0 && is_tab_line(lines[idx - 1].trim());
        let next_is_tab = lines.get(idx + 1).is_some_and(|l| is_tab_line(l.trim()));
        // Setas de batida logo embaixo da tab: ficam com a tab (com os espaços,
        // porque a coluna diz em que nota cai cada seta).
        let keep_raw = (is_tab_line(line))
            || (prev_is_tab && is_arrow_line(line))
            || (next_is_tab && chord_line(line).is_some());
        if keep_raw {
            let sec = current.get_or_insert_with(|| Section {
                name: format!("Parte {}", sections.len() + 1),
                repeat: 1,
                chords: Vec::new(),
                tab: String::new(),
                strum: None,
            });
            if !sec.tab.is_empty() {
                // Linha em branco entre um bloco e outro (acordes + tab + setas).
                let starts_block = next_is_tab && !is_tab_line(line);
                sec.tab.push('\n');
                if starts_block {
                    sec.tab.push('\n');
                }
            }
            if is_tab_line(line) {
                sec.tab.push_str(line);
            } else {
                // Acordes e setas mantêm o recuo, alinhados com a tab.
                sec.tab.push_str(raw.trim_end());
            }
            if !is_tab_line(line) && !is_arrow_line(line) {
                if let Some(cl) = chord_line(line) {
                    sec.chords.extend(cl.chords);
                    sec.repeat = sec.repeat.max(cl.repeat);
                }
            }
            continue;
        }

        if let Some(line) = chord_line(line) {
            let sec = current.get_or_insert_with(|| Section {
                name: format!("Parte {}", sections.len() + 1),
                repeat: 1,
                chords: Vec::new(),
                tab: String::new(),
                strum: None,
            });
            sec.chords.extend(line.chords);
            sec.repeat = sec.repeat.max(line.repeat);
        }
    }
    flush(&mut current, &mut sections);
    sections
}

/// Mesmo que [`parse`], em JSON: `[{"name":..,"repeat":..,"chords":[..]}]`.
pub fn parse_json(text: &str) -> String {
    serde_json::to_string(&parse(text)).unwrap_or_else(|_| "[]".into())
}

/// Cabeçalho de parte: devolve o nome e o resto da linha.
pub(crate) fn header(line: &str) -> Option<(String, &str)> {
    if let Some(rest) = line.strip_prefix('[') {
        let end = rest.find(']')?;
        let name = rest[..end].trim();
        if name.is_empty() || name.chars().count() > 40 {
            return None;
        }
        return Some((name.to_string(), &rest[end + 1..]));
    }
    // "Refrão:" sozinho na linha (e que não seja uma linha de acordes).
    if let Some(name) = line.strip_suffix(':') {
        let name = name.trim();
        if !name.is_empty() && name.chars().count() <= 30 && chord_line(name).is_none() {
            return Some((name.to_string(), ""));
        }
    }
    None
}

pub(crate) struct ChordLine {
    pub(crate) chords: Vec<String>,
    repeat: u32,
}

/// Uma linha que só tem acordes (e separadores ou marcas de repetição).
pub(crate) fn chord_line(line: &str) -> Option<ChordLine> {
    let mut chords = Vec::new();
    let mut repeat = 1;
    let cleaned: String = line
        .chars()
        .map(|c| if c == '|' { ' ' } else { c })
        .collect();
    for token in cleaned.split_whitespace() {
        if let Some(r) = repeat_mark(token) {
            repeat = r;
            continue;
        }
        let t = token.trim_matches(|c| c == '-' || c == '.' || c == ',');
        if t.is_empty() {
            continue;
        }
        // Parênteses em volta de um acorde: "(G)" vira "G", mas "A7(9)" fica.
        let t = if t.starts_with('(') && t.ends_with(')') {
            &t[1..t.len() - 1]
        } else {
            t
        };
        if is_chord_token(t) {
            chords.push(t.to_string());
        } else if let Some((a, b)) = split_glued(t) {
            // "FG" ou "AmG": acordes grudados (comum em texto lido de print).
            chords.push(a.to_string());
            chords.push(b.to_string());
        } else {
            return None;
        }
    }
    if chords.is_empty() {
        None
    } else {
        Some(ChordLine { chords, repeat })
    }
}

/// Divide dois acordes grudados ("FG", "Am7D") numa letra maiúscula de A a G.
fn split_glued(token: &str) -> Option<(&str, &str)> {
    token
        .char_indices()
        .skip(1)
        .filter(|(_, c)| ('A'..='G').contains(c))
        .map(|(i, _)| (&token[..i], &token[i..]))
        .find(|(a, b)| !a.ends_with('/') && is_chord_token(a) && is_chord_token(b))
}

/// Linha só com setas de batida (↓ ↑) e x de abafado.
pub(crate) fn is_arrow_line(line: &str) -> bool {
    line.chars()
        .any(|c| matches!(c, '↓' | '↑' | '⇣' | '⇡' | '⇓' | '⇑'))
        && line.chars().all(|c| {
            c.is_whitespace()
                || matches!(c, '↓' | '↑' | '⇣' | '⇡' | '⇓' | '⇑' | 'x' | 'X' | '✕' | '×')
        })
}

/// Linha de tablatura: "E|--3--", "e |-0-", "B|---|".
pub(crate) fn is_tab_line(line: &str) -> bool {
    let mut chars = line.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !"EADGBe".contains(first) {
        return false;
    }
    let rest = chars.as_str().trim_start();
    rest.starts_with('|') && rest.contains('-')
}

/// "2x", "x2", "(2x)", "(x2)", "2X".
fn repeat_mark(token: &str) -> Option<u32> {
    let t = token.trim_matches(|c| c == '(' || c == ')').to_lowercase();
    let digits = t
        .strip_suffix('x')
        .or_else(|| t.strip_prefix('x'))
        .filter(|d| !d.is_empty() && d.chars().all(|c| c.is_ascii_digit()))?;
    digits.parse().ok().filter(|&n| (1..=99).contains(&n))
}

/// Acorde de verdade, e não uma palavra da letra que começa com A–G
/// ("Eu", "Bem", "Do"): o sufixo só pode ter peças de nome de acorde.
pub fn is_chord_token(token: &str) -> bool {
    if !token.starts_with(|c: char| ('A'..='G').contains(&c)) {
        return false;
    }
    let Ok(chord) = token.parse::<Chord>() else {
        return false;
    };
    let mut rest = chord.suffix.as_str();
    const WORDS: [&str; 10] = [
        "maj", "min", "dim", "aug", "sus", "add", "no", "omit", "M", "m",
    ];
    'outer: while !rest.is_empty() {
        for w in WORDS {
            if let Some(r) = rest.strip_prefix(w) {
                rest = r;
                continue 'outer;
            }
        }
        let c = rest.chars().next().unwrap();
        if c.is_ascii_digit() || "#b+-()/º°ø,".contains(c) {
            rest = &rest[c.len_utf8()..];
        } else {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chord_tokens() {
        for ok in [
            "Am", "E", "C#m7", "Bb9(7)", "F#5(9)", "D7/F#", "Gsus4", "Cmaj7", "Bº", "A7M", "C6/9",
        ] {
            assert!(is_chord_token(ok), "{ok}");
        }
        for bad in ["Eu", "Bem", "Do", "As", "Ela", "Agora", "Ciúme", "e", "x"] {
            assert!(!is_chord_token(bad), "{bad}");
        }
    }

    #[test]
    fn reads_pasted_sheet() {
        let text = "\
Tom: G

[Intro] G  D  Em  C  (2x)

[Primeira Parte]
G            D
Uma linha de letra qualquer
Em           C
Outra linha da letra

E|-----3-----|
B|---0---0---|

Refrão:
| C  G | D  Em |
Eu canto aqui
";
        let s = parse(text);
        assert_eq!(s.len(), 3);
        assert_eq!(s[0].name, "Intro");
        assert_eq!(s[0].repeat, 2);
        assert_eq!(s[0].chords, ["G", "D", "Em", "C"]);
        assert_eq!(s[1].name, "Primeira Parte");
        assert_eq!(s[1].chords, ["G", "D", "Em", "C"]);
        assert_eq!(s[2].name, "Refrão");
        assert_eq!(s[2].chords, ["C", "G", "D", "Em"]);
        assert_eq!(s[1].tab, "E|-----3-----|\nB|---0---0---|");
    }

    #[test]
    fn keeps_chords_and_arrows_around_a_tab() {
        let text = "[Dedilhado]\nParte 1 de 2\n   Em      D\nE|--0--|\nB|-----|\n    ↓  ↑\n\n   Bm\nE|--2--|\n";
        let s = parse(text);
        assert_eq!(s.len(), 1);
        assert_eq!(s[0].chords, ["Em", "D", "Bm"]);
        assert_eq!(
            s[0].tab,
            "   Em      D\nE|--0--|\nB|-----|\n    ↓  ↑\n\n   Bm\nE|--2--|"
        );
        // A leitura da tab ignora as linhas de acordes e setas.
        assert_eq!(crate::tab::parse(&s[0].tab).len(), 3);
    }

    #[test]
    fn splits_glued_chords() {
        let s = parse("[Refrão]\nFG   Am\nD/F#  G");
        assert_eq!(s[0].chords, ["F", "G", "Am", "D/F#", "G"]);
    }

    #[test]
    fn keeps_tab_only_parts() {
        let s = parse("[Solo]\ne|-----|\nB|--3--|\nG|-----|");
        assert_eq!(s.len(), 1);
        assert!(s[0].chords.is_empty());
        assert_eq!(s[0].tab.lines().count(), 3);
    }

    #[test]
    fn chords_without_header_get_a_part() {
        let s = parse("Am F C G\nletra\nAm F C G x2");
        assert_eq!(s.len(), 1);
        assert_eq!(s[0].name, "Parte 1");
        assert_eq!(s[0].repeat, 2);
        assert_eq!(s[0].chords.len(), 8);
        assert_eq!(
            parse_json("[A] C"),
            r#"[{"name":"A","repeat":1,"chords":["C"]}]"#
        );
    }
}
