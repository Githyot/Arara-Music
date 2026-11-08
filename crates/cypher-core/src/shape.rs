//! Formas de acorde no braço do violão (afinação padrão E A D G B E).
//!
//! Para cada acorde escolhemos uma forma aberta conhecida (C, G, Am...) ou,
//! se não houver, uma forma móvel com pestana baseada na fundamental na 6ª
//! corda (forma de E) ou na 5ª corda (forma de A), pegando a que fica mais
//! perto da cabeça do violão. Assim todo acorde transposto também tem desenho.

use crate::chord::{Chord, Note};

/// Uma corda: casa pressionada (0 = solta) ou `None` se não for tocada.
pub type Fret = Option<u8>;

/// Forma de um acorde: casa e dedo para cada corda, da 6ª (Mi grave) à 1ª (Mi agudo).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChordShape {
    pub frets: [Fret; 6],
    /// Dedo da mão esquerda (1 indicador ... 4 mindinho), 0 = nenhum.
    pub fingers: [u8; 6],
    /// Corda (0 = 6ª) que toca a fundamental mais grave, para destacar no desenho.
    pub root_string: usize,
}

impl ChordShape {
    /// Primeira casa do desenho (1 se o acorde cabe junto da pestana do violão).
    pub fn base_fret(&self) -> u8 {
        let max = self.frets.iter().flatten().copied().max().unwrap_or(0);
        if max <= 4 {
            1
        } else {
            self.frets
                .iter()
                .flatten()
                .copied()
                .filter(|&f| f > 0)
                .min()
                .unwrap_or(1)
        }
    }

    /// JSON simples para o QML: `{"frets":[..],"fingers":[..],"base":n,"root":n}`,
    /// com -1 nas cordas não tocadas.
    pub fn to_json(&self) -> String {
        let frets: Vec<String> = self
            .frets
            .iter()
            .map(|f| f.map_or("-1".to_string(), |v| v.to_string()))
            .collect();
        let fingers: Vec<String> = self.fingers.iter().map(u8::to_string).collect();
        format!(
            "{{\"frets\":[{}],\"fingers\":[{}],\"base\":{},\"root\":{}}}",
            frets.join(","),
            fingers.join(","),
            self.base_fret(),
            self.root_string
        )
    }
}

/// Tipos de acorde que sabemos desenhar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Quality {
    Major,
    Minor,
    Dom7,
    Min7,
    Maj7,
    Power,
    PowerAdd9,
    Dom9,
    Sus4,
    Sus2,
    Min7b5,
    Dim,
    Six,
    Min6,
    Add4,
    Min11,
    Dom7Add4,
}

fn quality(suffix: &str) -> Option<Quality> {
    let s: String = suffix.chars().filter(|c| !c.is_whitespace()).collect();
    Some(match s.as_str() {
        "" | "M" | "maj" => Quality::Major,
        "m" | "min" | "-" => Quality::Minor,
        "7" => Quality::Dom7,
        "m7" | "min7" | "-7" => Quality::Min7,
        "7M" | "maj7" | "M7" | "7+" => Quality::Maj7,
        "5" => Quality::Power,
        "5(9)" | "5add9" | "5(add9)" | "(9)" | "add9" | "(add9)" => Quality::PowerAdd9,
        "9" | "7(9)" | "9(7)" => Quality::Dom9,
        "sus4" | "4" | "sus" => Quality::Sus4,
        "sus2" | "2" => Quality::Sus2,
        "m7(b5)" | "m7b5" | "ø" => Quality::Min7b5,
        "°" | "dim" | "º" | "o" => Quality::Dim,
        "6" => Quality::Six,
        "m6" => Quality::Min6,
        "add4" | "(add4)" | "add11" | "(4)" => Quality::Add4,
        "m11" | "m7(11)" | "m7add11" => Quality::Min11,
        "7add4" | "7(4)" | "7(11)" | "7add11" => Quality::Dom7Add4,
        _ => return None,
    })
}

/// (casa relativa à fundamental, dedo); `X` = corda não tocada.
type Tpl = [(i8, u8); 6];
const X: (i8, u8) = (-99, 0);

/// Formas móveis com a fundamental na 6ª corda (forma de E).
fn e_shape(q: Quality) -> Option<Tpl> {
    Some(match q {
        Quality::Major => [(0, 1), (2, 3), (2, 4), (1, 2), (0, 1), (0, 1)],
        Quality::Minor => [(0, 1), (2, 3), (2, 4), (0, 1), (0, 1), (0, 1)],
        Quality::Dom7 => [(0, 1), (2, 3), (0, 1), (1, 2), (0, 1), (0, 1)],
        Quality::Min7 => [(0, 1), (2, 3), (0, 1), (0, 1), (0, 1), (0, 1)],
        Quality::Maj7 => [(0, 1), X, (1, 2), (1, 3), (0, 1), X],
        Quality::Power => [(0, 1), (2, 3), (2, 4), X, X, X],
        Quality::PowerAdd9 => [(0, 1), (2, 3), (4, 4), X, X, X],
        Quality::Sus4 => [(0, 1), (2, 2), (2, 3), (2, 4), (0, 1), (0, 1)],
        Quality::Min7b5 => [(0, 2), X, (0, 3), (0, 4), (-1, 1), X],
        Quality::Dim => [(0, 2), X, (-1, 1), (0, 3), (-1, 1), X],
        Quality::Six => [(0, 2), X, (-1, 1), (1, 3), (0, 4), X],
        Quality::Min6 => [(0, 2), X, (-1, 1), (0, 3), (0, 4), X],
        Quality::Min11 => [(0, 2), X, (0, 3), (0, 4), (-2, 1), (-2, 1)],
        Quality::Dom7Add4 => [(0, 2), X, (0, 3), (1, 4), (-2, 1), (-2, 1)],
        Quality::Dom9 | Quality::Sus2 | Quality::Add4 => return None,
    })
}

/// Formas móveis com a fundamental na 5ª corda (forma de A).
fn a_shape(q: Quality) -> Option<Tpl> {
    Some(match q {
        Quality::Major => [X, (0, 1), (2, 2), (2, 3), (2, 4), (0, 1)],
        Quality::Minor => [X, (0, 1), (2, 3), (2, 4), (1, 2), (0, 1)],
        Quality::Dom7 => [X, (0, 1), (2, 3), (0, 1), (2, 4), (0, 1)],
        Quality::Min7 => [X, (0, 1), (2, 3), (0, 1), (1, 2), (0, 1)],
        Quality::Maj7 => [X, (0, 1), (2, 3), (1, 2), (2, 4), (0, 1)],
        Quality::Power => [X, (0, 1), (2, 3), (2, 4), X, X],
        Quality::PowerAdd9 => [X, (0, 1), (2, 3), (4, 4), X, X],
        Quality::Dom9 => [X, (0, 2), (-1, 1), (0, 3), (0, 3), (0, 3)],
        Quality::Sus4 => [X, (0, 1), (2, 2), (2, 3), (3, 4), (0, 1)],
        Quality::Sus2 => [X, (0, 1), (2, 3), (2, 4), (0, 1), (0, 1)],
        Quality::Min7b5 => [X, (0, 2), (1, 3), (0, 1), (1, 4), X],
        Quality::Dim => [X, (0, 2), (1, 3), (2, 4), (1, 1), X],
        Quality::Six => [X, (0, 1), (2, 3), (2, 3), (2, 3), (2, 3)],
        Quality::Min6 => [X, (0, 2), (-1, 1), (1, 3), (0, 1), X],
        // Sem a terça, como o Badd4 x24400: na prática soa como um sus4.
        Quality::Add4 => [X, (0, 1), (2, 2), (2, 3), (3, 4), (0, 1)],
        Quality::Min11 | Quality::Dom7Add4 => return None,
    })
}

/// Forma aberta: (classe da fundamental, qualidade, casas com -1 = não tocar,
/// dedos, corda da fundamental).
type OpenShape = (u8, Quality, [i8; 6], [u8; 6], usize);

/// Formas abertas clássicas.
#[rustfmt::skip]
const OPEN: &[OpenShape] = &[
    (0,  Quality::Major, [-1, 3, 2, 0, 1, 0], [0, 3, 2, 0, 1, 0], 1), // C
    (0,  Quality::Dom7,  [-1, 3, 2, 3, 1, 0], [0, 3, 2, 4, 1, 0], 1), // C7
    (0,  Quality::Maj7,  [-1, 3, 2, 0, 0, 0], [0, 3, 2, 0, 0, 0], 1), // C7M
    (0,  Quality::PowerAdd9, [-1, 3, 0, 0, 3, 3], [0, 2, 0, 0, 3, 4], 1), // C(9)
    (2,  Quality::Major, [-1, -1, 0, 2, 3, 2], [0, 0, 0, 1, 3, 2], 2), // D
    (2,  Quality::Minor, [-1, -1, 0, 2, 3, 1], [0, 0, 0, 2, 3, 1], 2), // Dm
    (2,  Quality::Dom7,  [-1, -1, 0, 2, 1, 2], [0, 0, 0, 2, 1, 3], 2), // D7
    (2,  Quality::Min7,  [-1, -1, 0, 2, 1, 1], [0, 0, 0, 2, 1, 1], 2), // Dm7
    (2,  Quality::Maj7,  [-1, -1, 0, 2, 2, 2], [0, 0, 0, 1, 1, 1], 2), // D7M
    (2,  Quality::Power, [-1, -1, 0, 2, 3, -1], [0, 0, 0, 1, 3, 0], 2), // D5
    (2,  Quality::Sus4,  [-1, -1, 0, 2, 3, 3], [0, 0, 0, 1, 2, 3], 2), // Dsus4
    (2,  Quality::Sus2,  [-1, -1, 0, 2, 3, 0], [0, 0, 0, 1, 3, 0], 2), // Dsus2
    (4,  Quality::Major, [0, 2, 2, 1, 0, 0], [0, 2, 3, 1, 0, 0], 0), // E
    (4,  Quality::Minor, [0, 2, 2, 0, 0, 0], [0, 2, 3, 0, 0, 0], 0), // Em
    (4,  Quality::Dom7,  [0, 2, 0, 1, 0, 0], [0, 2, 0, 1, 0, 0], 0), // E7
    (4,  Quality::Min7,  [0, 2, 0, 0, 0, 0], [0, 2, 0, 0, 0, 0], 0), // Em7
    (4,  Quality::Power, [0, 2, 2, -1, -1, -1], [0, 1, 2, 0, 0, 0], 0), // E5
    (4,  Quality::Maj7,  [0, 2, 1, 1, 0, 0], [0, 3, 1, 2, 0, 0], 0), // E7M
    (4,  Quality::Sus4,  [0, 2, 2, 2, 0, 0], [0, 2, 3, 4, 0, 0], 0), // Esus4
    (7,  Quality::Major, [3, 2, 0, 0, 0, 3], [2, 1, 0, 0, 0, 3], 0), // G
    (7,  Quality::Dom7,  [3, 2, 0, 0, 0, 1], [3, 2, 0, 0, 0, 1], 0), // G7
    (9,  Quality::Major, [-1, 0, 2, 2, 2, 0], [0, 0, 1, 2, 3, 0], 1), // A
    (9,  Quality::Minor, [-1, 0, 2, 2, 1, 0], [0, 0, 2, 3, 1, 0], 1), // Am
    (9,  Quality::Dom7,  [-1, 0, 2, 0, 2, 0], [0, 0, 2, 0, 3, 0], 1), // A7
    (9,  Quality::Min7,  [-1, 0, 2, 0, 1, 0], [0, 0, 2, 0, 1, 0], 1), // Am7
    (9,  Quality::Maj7,  [-1, 0, 2, 1, 2, 0], [0, 0, 2, 1, 3, 0], 1), // A7M
    (9,  Quality::Power, [-1, 0, 2, 2, -1, -1], [0, 0, 1, 2, 0, 0], 1), // A5
    (9,  Quality::Sus4,  [-1, 0, 2, 2, 3, 0], [0, 0, 1, 2, 3, 0], 1), // Asus4
    (9,  Quality::Sus2,  [-1, 0, 2, 2, 0, 0], [0, 0, 1, 2, 0, 0], 1), // Asus2
    (11, Quality::Dom7,  [-1, 2, 1, 2, 0, 2], [0, 2, 1, 3, 0, 4], 1), // B7
    (11, Quality::Add4,  [-1, 2, 4, 4, 0, 0], [0, 1, 3, 4, 0, 0], 1), // Badd4
];

fn from_template(tpl: &Tpl, root_fret: i8, root_string: usize) -> Option<ChordShape> {
    let mut frets = [None; 6];
    let mut fingers = [0u8; 6];
    for (i, &(off, finger)) in tpl.iter().enumerate() {
        if off == X.0 {
            continue;
        }
        let f = root_fret + off;
        if !(0..=15).contains(&f) {
            return None;
        }
        frets[i] = Some(f as u8);
        // Na casa 0 a "pestana" é a do próprio violão: sem dedo.
        fingers[i] = if f == 0 { 0 } else { finger };
    }
    Some(ChordShape {
        frets,
        fingers,
        root_string,
    })
}

fn highest_fret(shape: &ChordShape) -> u8 {
    shape.frets.iter().flatten().copied().max().unwrap_or(0)
}

/// Forma para tocar o acorde, se o tipo for conhecido.
pub fn shape_for(chord: &Chord) -> Option<ChordShape> {
    let q = quality(&chord.suffix)?;
    let root = chord.root.semitone();

    if chord.bass.is_none() {
        if let Some(&(_, _, frets, fingers, rs)) =
            OPEN.iter().find(|(r, oq, ..)| *r == root && *oq == q)
        {
            return Some(ChordShape {
                frets: frets.map(|f| if f < 0 { None } else { Some(f as u8) }),
                fingers,
                root_string: rs,
            });
        }
    }

    let fret_on = |open: Note| (root as i8 - open.semitone() as i8).rem_euclid(12);
    let mut candidates = Vec::new();
    for (tpl, open, string) in [
        (e_shape(q), Note::from_semitone(4), 0usize),
        (a_shape(q), Note::from_semitone(9), 1usize),
    ] {
        if let Some(tpl) = tpl {
            let base = fret_on(open);
            // Uma oitava acima quando a forma precisaria de casa negativa.
            for r in [base, base + 12] {
                if let Some(s) = from_template(&tpl, r, string) {
                    candidates.push(s);
                    break;
                }
            }
        }
    }
    candidates.into_iter().min_by_key(highest_fret)
}

/// Atalho: forma a partir do nome, em JSON para o QML, ou vazio se não souber.
pub fn shape_json(name: &str) -> String {
    name.parse::<Chord>()
        .ok()
        .and_then(|c| shape_for(&c).or_else(|| crate::chorddb::shapes(&c).into_iter().next()))
        .map(|s| s.to_json())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frets(name: &str) -> [i8; 6] {
        let s = shape_for(&name.parse().unwrap()).unwrap();
        s.frets.map(|f| f.map_or(-1, |v| v as i8))
    }

    #[test]
    fn open_chords() {
        assert_eq!(frets("C"), [-1, 3, 2, 0, 1, 0]);
        assert_eq!(frets("Em"), [0, 2, 2, 0, 0, 0]);
        assert_eq!(frets("D5"), [-1, -1, 0, 2, 3, -1]);
    }

    #[test]
    fn movable_shapes() {
        // F#5(9) como na aula: 2ª casa na 6ª corda, 4ª na 5ª, 6ª na 4ª.
        assert_eq!(frets("F#5(9)"), [2, 4, 6, -1, -1, -1]);
        assert_eq!(frets("C#5"), [-1, 4, 6, 6, -1, -1]);
        assert_eq!(frets("Fm7"), [1, 3, 1, 1, 1, 1]);
        assert_eq!(frets("F"), [1, 3, 3, 2, 1, 1]);
        assert_eq!(frets("Bb9(7)"), [-1, 1, 0, 1, 1, 1]);
        assert_eq!(frets("G#5"), [4, 6, 6, -1, -1, -1]);
        assert_eq!(frets("Bm"), [-1, 2, 4, 4, 3, 2]);
        assert_eq!(frets("F#m11"), [2, -1, 2, 2, 0, 0]);
        assert_eq!(frets("F#7add4"), [2, -1, 2, 3, 0, 0]);
        assert_eq!(frets("Badd4"), [-1, 2, 4, 4, 0, 0]);
        assert_eq!(frets("Emaj7"), [0, 2, 1, 1, 0, 0]);
        assert_eq!(frets("C#m7"), [-1, 4, 6, 4, 5, 4]);
    }

    #[test]
    fn transposed_chords_still_have_shapes() {
        for name in [
            "Fm7", "C#5", "Bb9(7)", "F#5(9)", "G#5", "F5", "Bb5", "Badd4", "F#m11", "F#7add4",
        ] {
            let chord: Chord = name.parse().unwrap();
            for st in 0..12 {
                assert!(shape_for(&chord.transpose(st)).is_some(), "{name} +{st}");
            }
        }
    }

    #[test]
    fn base_fret_and_json() {
        let s = shape_for(&"F#5(9)".parse().unwrap()).unwrap();
        assert_eq!(s.base_fret(), 2);
        assert_eq!(
            s.to_json(),
            "{\"frets\":[2,4,6,-1,-1,-1],\"fingers\":[1,3,4,0,0,0],\"base\":2,\"root\":0}"
        );
        assert_eq!(shape_json("Hmm"), "");
        assert_eq!(shape_json("Cxyz"), "");
    }
}
