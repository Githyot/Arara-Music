//! Importar uma música inteira de um texto (colado, arquivo .txt ou página
//! de cifra): além das partes e acordes (ver [`crate::sheet`]), lê
//!
//! - a primeira linha "Artista - Música";
//! - "Tom: Fm (com forma de Em)" e "Capotraste na 1ª casa";
//! - blocos de batida: `[Refrão - Parte 1] 120 bpm`, uma linha de setas
//!   (↓ ↑, com `x` em cima para abafar) e a contagem `1 . 2 . 3 . 4`;
//! - a lista de formas no fim: `Fm = 0 2 2 0 0 0` (com capotraste, os nomes
//!   da lista são o som real e as partes usam o nome da forma, e as casas
//!   contam a partir do capo: o app soma o capo para ficar igual à tab);
//! - partes que repetem a mesma sequência viram "N×".

use crate::chord::transpose_name;
use crate::sheet::{self, Section};
use crate::Chord;
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Strum {
    pub name: String,
    pub pattern: Vec<String>,
    pub counts: Vec<String>,
    #[serde(skip_serializing_if = "is_zero")]
    pub bpm: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Voicing {
    pub frets: [i8; 6],
    pub fingers: [u8; 6],
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Default)]
pub struct Song {
    pub title: String,
    pub artist: String,
    pub key: String,
    pub capo: u32,
    #[serde(skip_serializing_if = "is_zero")]
    pub bpm: u32,
    pub sections: Vec<Section>,
    pub strums: Vec<Strum>,
    pub voicings: BTreeMap<String, Voicing>,
}

fn is_zero(n: &u32) -> bool {
    *n == 0
}

pub fn parse(text: &str) -> Song {
    let lines: Vec<&str> = text.lines().collect();
    let mut song = Song::default();
    let mut keep = vec![true; lines.len()];
    let mut list: Vec<(String, [i8; 6])> = Vec::new();

    // Primeira linha com texto: "Artista - Música", se não for parte nem acordes.
    if let Some((i, first)) = lines.iter().enumerate().find(|(_, l)| !l.trim().is_empty()) {
        let t = first.trim();
        if let Some((a, b)) = t.split_once(" - ") {
            if sheet::header(t).is_none() && sheet::chord_line(t).is_none() {
                song.artist = a.trim().to_string();
                song.title = b.trim().to_string();
                keep[i] = false;
            }
        }
    }

    let mut i = 0;
    while i < lines.len() {
        let t = lines[i].trim();
        let lower = t.to_lowercase();
        if let Some(rest) = lower.strip_prefix("tom:") {
            song.key = key_from(&t[t.len() - rest.len()..]);
            keep[i] = false;
        } else if lower.starts_with("capotraste") || lower.starts_with("capo:") {
            song.capo = first_number(&lower).unwrap_or(0);
            keep[i] = false;
        } else if let Some((name, frets)) = shape_line(t) {
            list.push((name, frets));
            keep[i] = false;
        } else if t.starts_with("---") && lower.contains("acordes") {
            keep[i] = false;
        } else if let Some((name, rest)) = sheet::header(t) {
            let bpm = bpm_in(rest);
            if bpm > 0 && song.bpm == 0 {
                song.bpm = bpm;
            }
            // Bloco só com setas e contagem até a próxima parte: é uma batida.
            let mut j = i + 1;
            let mut block = Vec::new();
            while j < lines.len() && sheet::header(lines[j].trim()).is_none() {
                if !lines[j].trim().is_empty() {
                    block.push(lines[j]);
                }
                j += 1;
            }
            let all_strum = !block.is_empty()
                && block
                    .iter()
                    .all(|l| is_arrow_line(l) || is_count_line(l) || is_mute_line(l))
                && block.iter().any(|l| is_arrow_line(l));
            if all_strum {
                let mut s = strum_from(&block);
                s.name = name;
                s.bpm = bpm;
                song.strums.push(s);
                for k in keep.iter_mut().take(j).skip(i) {
                    *k = false;
                }
                i = j;
                continue;
            }
        }
        i += 1;
    }

    let rest: Vec<&str> = lines
        .iter()
        .zip(&keep)
        .filter(|(_, k)| **k)
        .map(|(l, _)| *l)
        .collect();
    song.sections = sheet::parse(&rest.join("\n"));
    for sec in &mut song.sections {
        collapse(sec);
        sec.strum = song
            .strums
            .iter()
            .position(|s| s.name == sec.name || s.name.starts_with(&format!("{} ", sec.name)));
    }

    // Sem "Tom:", o tom é o do primeiro acorde.
    if song.key.is_empty() {
        if let Some(c) = song
            .sections
            .iter()
            .flat_map(|s| s.chords.first())
            .find_map(|t| t.parse::<Chord>().ok())
        {
            song.key = format!(
                "{}{}",
                c.root.name(c.accidental),
                if c.is_minor() { "m" } else { "" }
            );
        }
    }

    // Formas da lista: com capotraste, o nome da lista soa `capo` casas acima.
    for sec in &song.sections {
        for token in &sec.chords {
            if song.voicings.contains_key(token) {
                continue;
            }
            if let Some((_, frets)) = list
                .iter()
                .find(|(n, _)| same_chord(&transpose_name(n, -(song.capo as i32)), token))
            {
                // A lista conta as casas a partir do capotraste; o app (como a
                // tab e o desenho com "11ª") usa a casa de verdade no braço.
                let mut abs = *frets;
                for f in abs.iter_mut() {
                    if *f > 0 {
                        *f += song.capo as i8;
                    }
                }
                song.voicings.insert(
                    token.clone(),
                    Voicing {
                        frets: abs,
                        fingers: fingers_for(&abs),
                    },
                );
            }
        }
    }
    song
}

pub fn parse_json(text: &str) -> String {
    serde_json::to_string(&parse(text)).unwrap_or_else(|_| "{}".into())
}

/// "Fm (com forma de Em)" -> "Em": as partes estão escritas na forma.
pub(crate) fn key_from(s: &str) -> String {
    let lower = s.to_lowercase();
    let pick = |t: &str| {
        t.split(|c: char| c.is_whitespace() || c == '(' || c == ')')
            .find(|w| sheet::is_chord_token(w))
            .map(str::to_string)
    };
    if let Some(i) = lower.find("forma de") {
        if let Some(k) = pick(&s[i + "forma de".len()..]) {
            return k;
        }
    }
    pick(s).unwrap_or_default()
}

fn first_number(s: &str) -> Option<u32> {
    let d: String = s
        .chars()
        .skip_while(|c| !c.is_ascii_digit())
        .take_while(|c| c.is_ascii_digit())
        .collect();
    d.parse().ok()
}

/// "120 bpm" (em qualquer lugar do resto da linha).
pub(crate) fn bpm_in(s: &str) -> u32 {
    let lower = s.to_lowercase();
    let Some(i) = lower.find("bpm") else {
        return 0;
    };
    let digits: String = lower[..i]
        .trim_end()
        .chars()
        .rev()
        .take_while(|c| c.is_ascii_digit())
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    digits
        .parse()
        .ok()
        .filter(|n| (20..=300).contains(n))
        .unwrap_or(0)
}

/// "Fm7(9) = 0 X 12 11 X X" (seis casas, X = não toca).
fn shape_line(t: &str) -> Option<(String, [i8; 6])> {
    let (name, frets) = t.split_once('=')?;
    let name = name.trim();
    if !sheet::is_chord_token(name) {
        return None;
    }
    let parts: Vec<&str> = frets.split_whitespace().collect();
    if parts.len() != 6 {
        return None;
    }
    let mut out = [0i8; 6];
    for (o, p) in out.iter_mut().zip(&parts) {
        *o = if p.eq_ignore_ascii_case("x") {
            -1
        } else {
            p.parse::<i8>().ok().filter(|f| (0..=24).contains(f))?
        };
    }
    Some((name.to_string(), out))
}

fn same_chord(a: &str, b: &str) -> bool {
    match (a.parse::<Chord>(), b.parse::<Chord>()) {
        (Ok(x), Ok(y)) => {
            x.root.semitone() == y.root.semitone()
                && x.suffix == y.suffix
                && x.bass.map(|n| n.semitone()) == y.bass.map(|n| n.semitone())
        }
        _ => false,
    }
}

/// Dedos prováveis: em ordem de casa, 1 a 4; com mais de 4 notas, a casa
/// mais baixa vira pestana (dedo 1).
fn fingers_for(frets: &[i8; 6]) -> [u8; 6] {
    let mut notes: Vec<(i8, usize)> = (0..6)
        .filter(|&s| frets[s] > 0)
        .map(|s| (frets[s], s))
        .collect();
    notes.sort();
    let mut out = [0u8; 6];
    if notes.is_empty() {
        return out;
    }
    let min = notes[0].0;
    let barre = notes.len() > 4;
    // Cada dedo depois do anterior, e mais longe quanto mais alta a casa.
    let mut prev = if barre { 1 } else { 0 };
    for (f, s) in notes {
        if barre && f == min {
            out[s] = 1;
        } else {
            let finger = (prev + 1).max(1 + (f - min) as u8).min(4);
            out[s] = finger;
            prev = finger;
        }
    }
    out
}

fn is_arrow(c: char) -> bool {
    matches!(c, '↓' | '↑' | '⇣' | '⇡' | '🡓' | '🡑')
}

fn is_arrow_line(l: &str) -> bool {
    l.chars().any(is_arrow)
        && l.chars()
            .all(|c| c.is_whitespace() || is_arrow(c) || "xX✕×".contains(c))
}

fn is_mute_line(l: &str) -> bool {
    let t = l.trim();
    !t.is_empty() && t.chars().all(|c| c.is_whitespace() || "xX✕×".contains(c))
}

/// "1 . 2 . 3 . 4 ." ou "1 e 2 e 3 e 4 e".
fn is_count_line(l: &str) -> bool {
    let t = l.trim();
    t.starts_with('1')
        && t.chars().any(|c| c == '2')
        && t.chars()
            .all(|c| c.is_whitespace() || c.is_ascii_digit() || ".·˙ˑ'e&+a|-".contains(c))
}

/// Setas -> batida. Com a linha de contagem, a coluna de cada seta diz em que
/// pedaço do tempo ela cai; sem contagem, cada seta é uma colcheia.
fn strum_from(block: &[&str]) -> Strum {
    let arrows_at = block.iter().position(|l| is_arrow_line(l)).unwrap_or(0);
    let arrow_line: Vec<char> = block[arrows_at].chars().collect();
    let mute: Vec<char> = if arrows_at > 0 && is_mute_line(block[arrows_at - 1]) {
        block[arrows_at - 1].chars().collect()
    } else {
        Vec::new()
    };
    let count: Option<Vec<char>> = block[arrows_at + 1..]
        .iter()
        .find(|l| is_count_line(l))
        .map(|l| l.chars().collect());

    let muted_at = |col: usize| {
        let near = |v: &Vec<char>, c: usize| v.get(c).is_some_and(|ch| "xX✕×".contains(*ch));
        near(&mute, col) || (col > 0 && near(&mute, col - 1)) || near(&mute, col + 1)
    };
    let code = |c: char, col: usize| -> String {
        let up = c == '↑' || c == '⇡' || c == '🡑';
        if "xX✕×".contains(c) || (muted_at(col) && !up) {
            "X".into()
        } else if muted_at(col) {
            "XU".into()
        } else if up {
            "U".into()
        } else {
            "D".into()
        }
    };
    let strokes: Vec<(usize, char)> = arrow_line
        .iter()
        .enumerate()
        .filter(|(_, c)| is_arrow(**c) || "xX✕×".contains(**c))
        .map(|(i, c)| (i, *c))
        .collect();

    let beats: Vec<usize> = count
        .as_ref()
        .map(|c| {
            c.iter()
                .enumerate()
                .filter(|(_, ch)| ch.is_ascii_digit())
                .map(|(i, _)| i)
                .collect()
        })
        .unwrap_or_default();
    if beats.len() >= 2 {
        let width = (beats[beats.len() - 1] - beats[0]) as f32 / (beats.len() - 1) as f32;
        let offs: Vec<f32> = strokes
            .iter()
            .map(|(col, _)| (*col as f32 - beats[0] as f32) / width)
            .collect();
        let fits = |sub: f32| {
            offs.iter()
                .all(|o| ((o * sub) - (o * sub).round()).abs() <= 0.3)
        };
        let sub = if fits(2.0) { 2 } else { 4 };
        let slots = beats.len() * sub;
        let mut pattern = vec![String::new(); slots];
        for ((col, c), o) in strokes.iter().zip(&offs) {
            let k = (o * sub as f32).round().max(0.0) as usize;
            if k < slots {
                pattern[k] = code(*c, *col);
            }
        }
        let names: &[&str] = if sub == 2 {
            &["", "e"]
        } else {
            &["", "e", "&", "a"]
        };
        let counts = (0..slots)
            .map(|k| {
                if k % sub == 0 {
                    (k / sub + 1).to_string()
                } else {
                    names[k % sub].to_string()
                }
            })
            .collect();
        return Strum {
            name: String::new(),
            pattern,
            counts,
            bpm: 0,
        };
    }
    let pattern: Vec<String> = strokes.iter().map(|(col, c)| code(*c, *col)).collect();
    let counts = (0..pattern.len())
        .map(|k| {
            if k % 2 == 0 {
                (k / 2 + 1).to_string()
            } else {
                "e".into()
            }
        })
        .collect();
    Strum {
        name: String::new(),
        pattern,
        counts,
        bpm: 0,
    }
}

/// [A B A B A B] 1× -> [A B] 3×.
fn collapse(sec: &mut Section) {
    let n = sec.chords.len();
    for p in 1..=n / 2 {
        if n % p == 0 && (p..n).all(|i| sec.chords[i] == sec.chords[i % p]) {
            sec.repeat *= (n / p) as u32;
            sec.chords.truncate(p);
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "\
Banda Exemplo - Canção Inventada

Tom: Gm (com forma de F#m)
[Refrão - Parte 1] 96 bpm

        x
↓   ↓   ↓ ↑
1 . 2 . 3 . 4 .

[Intro] F#m  D  A  E

[Primeira Parte]
F#m           D
uma linha de letra
A             E
outra linha
F#m           D
mais uma
A             E
e outra

[Refrão]
D   E
la la la

----------------- Acordes -----------------
Capotraste na 1ª casa
Gm = 2 4 4 2 2 2
D# = X X 1 3 4 3
A# = X 1 3 3 3 1
F = 1 3 3 2 1 1
";

    #[test]
    fn reads_header_strum_shapes_and_repeats() {
        let s = parse(SAMPLE);
        assert_eq!(
            (s.artist.as_str(), s.title.as_str()),
            ("Banda Exemplo", "Canção Inventada")
        );
        assert_eq!((s.key.as_str(), s.capo, s.bpm), ("F#m", 1, 96));
        assert_eq!(s.strums.len(), 1);
        assert_eq!(s.strums[0].name, "Refrão - Parte 1");
        assert_eq!(s.strums[0].pattern, ["D", "", "D", "", "X", "U", "", ""]);
        assert_eq!(s.strums[0].counts[..3], ["1", "e", "2"]);
        let names: Vec<&str> = s.sections.iter().map(|x| x.name.as_str()).collect();
        assert_eq!(names, ["Intro", "Primeira Parte", "Refrão"]);
        assert_eq!(s.sections[1].chords, ["F#m", "D", "A", "E"]);
        assert_eq!(s.sections[1].repeat, 2);
        assert_eq!(s.sections[2].strum, Some(0));
        assert_eq!(s.sections[0].strum, None);
        // Gm com capo 1 é a forma de F#m.
        // Casas da lista + capo = casas de verdade (as mesmas da tab).
        assert_eq!(s.voicings["F#m"].frets, [3, 5, 5, 3, 3, 3]);
        assert_eq!(s.voicings["F#m"].fingers, [1, 3, 4, 1, 1, 1]);
        assert_eq!(s.voicings["D"].frets, [-1, -1, 2, 4, 5, 4]);
        assert_eq!(s.voicings["E"].frets, [2, 4, 4, 3, 2, 2]);
    }

    #[test]
    fn arrows_without_count_and_small_bits() {
        let st = strum_from(&["↓ ↓ ↑ ↑ ↓ ↑"]);
        assert_eq!(st.pattern, ["D", "D", "U", "U", "D", "U"]);
        assert_eq!(bpm_in(" 120 bpm"), 120);
        assert_eq!(bpm_in("(2x)"), 0);
        assert_eq!(key_from(" Fm (com forma de Em)"), "Em");
        assert_eq!(key_from(" C"), "C");
        assert_eq!(
            shape_line("Cm11 = X 2 4 4 3 0").unwrap().1,
            [-1, 2, 4, 4, 3, 0]
        );
        assert!(shape_line("Isso = nada").is_none());
    }
}
