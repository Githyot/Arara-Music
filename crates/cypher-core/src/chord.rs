//! Acordes: leitura de nomes como `C#m7/G#`, transposição e escrita.

use std::fmt;
use std::str::FromStr;

/// Como escrever as notas com acidente: `C#` (sustenido) ou `Db` (bemol).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Accidental {
    #[default]
    Sharp,
    Flat,
}

/// Uma das 12 notas da escala cromática (classe de altura, de 0 = Dó a 11 = Si).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Note(u8);

const SHARP_NAMES: [&str; 12] = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
];
const FLAT_NAMES: [&str; 12] = [
    "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B",
];

impl Note {
    /// Cria a nota a partir da classe de altura (qualquer inteiro, reduzido módulo 12).
    pub fn from_semitone(semitone: i32) -> Self {
        Note(semitone.rem_euclid(12) as u8)
    }

    /// Classe de altura de 0 (Dó) a 11 (Si).
    pub fn semitone(self) -> u8 {
        self.0
    }

    /// Sobe (ou desce, se negativo) a nota em semitons.
    pub fn transpose(self, semitones: i32) -> Self {
        Note::from_semitone(self.0 as i32 + semitones)
    }

    /// Nome da nota com o acidente escolhido.
    pub fn name(self, accidental: Accidental) -> &'static str {
        match accidental {
            Accidental::Sharp => SHARP_NAMES[self.0 as usize],
            Accidental::Flat => FLAT_NAMES[self.0 as usize],
        }
    }

    /// Lê uma nota no começo do texto. Devolve a nota, o acidente usado
    /// (se houver) e quantos bytes foram consumidos.
    fn parse_prefix(text: &str) -> Option<(Note, Option<Accidental>, usize)> {
        let mut chars = text.chars();
        let base = match chars.next()?.to_ascii_uppercase() {
            'C' => 0,
            'D' => 2,
            'E' => 4,
            'F' => 5,
            'G' => 7,
            'A' => 9,
            'B' => 11,
            _ => return None,
        };
        match chars.next() {
            Some('#') | Some('♯') => {
                let len = 1 + text[1..].chars().next().map_or(0, char::len_utf8);
                Some((Note::from_semitone(base + 1), Some(Accidental::Sharp), len))
            }
            Some('b') | Some('♭') => {
                let len = 1 + text[1..].chars().next().map_or(0, char::len_utf8);
                Some((Note::from_semitone(base - 1), Some(Accidental::Flat), len))
            }
            _ => Some((Note::from_semitone(base), None, 1)),
        }
    }
}

/// Erro ao ler o nome de um acorde.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseChordError(pub String);

impl fmt::Display for ParseChordError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "acorde inválido: {}", self.0)
    }
}

impl std::error::Error for ParseChordError {}

/// Um acorde como `Am7`, `F#m7(b5)` ou `G/B`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Chord {
    /// Nota fundamental.
    pub root: Note,
    /// Tudo que vem depois da fundamental: `m`, `7`, `maj7`, `sus4`, `m7(b5)`...
    pub suffix: String,
    /// Baixo invertido (o que vem depois da barra), se houver.
    pub bass: Option<Note>,
    /// Acidente usado ao escrever o acorde.
    pub accidental: Accidental,
}

impl Chord {
    /// Transpõe o acorde mantendo o estilo de acidente.
    pub fn transpose(&self, semitones: i32) -> Chord {
        Chord {
            root: self.root.transpose(semitones),
            suffix: self.suffix.clone(),
            bass: self.bass.map(|b| b.transpose(semitones)),
            accidental: self.accidental,
        }
    }

    /// Mesmo acorde, escrito com outro acidente.
    pub fn with_accidental(mut self, accidental: Accidental) -> Chord {
        self.accidental = accidental;
        self
    }

    /// Verdadeiro para acordes menores (`m`, `m7`, `min`...), mas não `maj7`.
    pub fn is_minor(&self) -> bool {
        let s = self.suffix.as_str();
        (s.starts_with('m') && !s.starts_with("maj")) || s.starts_with('-')
    }
}

impl FromStr for Chord {
    type Err = ParseChordError;

    fn from_str(text: &str) -> Result<Self, Self::Err> {
        let text = text.trim();
        let err = || ParseChordError(text.to_string());
        let (root, root_acc, used) = Note::parse_prefix(text).ok_or_else(err)?;
        let rest = &text[used..];

        let (suffix, bass, bass_acc) = match rest.rfind('/') {
            Some(slash) => {
                let bass_text = &rest[slash + 1..];
                match Note::parse_prefix(bass_text) {
                    Some((bass, acc, n)) if n == bass_text.len() => {
                        (&rest[..slash], Some(bass), acc)
                    }
                    // Algo como `C6/9`: a barra faz parte do sufixo.
                    _ => (rest, None, None),
                }
            }
            None => (rest, None, None),
        };

        if suffix.chars().any(char::is_whitespace) {
            return Err(err());
        }

        Ok(Chord {
            root,
            suffix: suffix.to_string(),
            bass,
            accidental: root_acc.or(bass_acc).unwrap_or_default(),
        })
    }
}

impl fmt::Display for Chord {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}{}", self.root.name(self.accidental), self.suffix)?;
        if let Some(bass) = self.bass {
            write!(f, "/{}", bass.name(self.accidental))?;
        }
        Ok(())
    }
}

/// Transpõe o nome de um acorde. Se não for um acorde válido, devolve o texto como veio.
pub fn transpose_name(name: &str, semitones: i32) -> String {
    match name.parse::<Chord>() {
        Ok(chord) => chord.transpose(semitones).to_string(),
        Err(_) => name.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(s: &str) -> Chord {
        s.parse().unwrap()
    }

    #[test]
    fn parses_simple_chords() {
        let am = c("Am");
        assert_eq!(am.root, Note::from_semitone(9));
        assert_eq!(am.suffix, "m");
        assert!(am.is_minor());
        assert_eq!(am.bass, None);
    }

    #[test]
    fn parses_accidentals_and_bass() {
        let ch = c("F#m7/C#");
        assert_eq!(ch.root.semitone(), 6);
        assert_eq!(ch.suffix, "m7");
        assert_eq!(ch.bass, Some(Note::from_semitone(1)));
        assert_eq!(ch.accidental, Accidental::Sharp);

        let bb = c("Bb7M");
        assert_eq!(bb.root.semitone(), 10);
        assert_eq!(bb.accidental, Accidental::Flat);
        assert!(!c("Cmaj7").is_minor());
    }

    #[test]
    fn slash_inside_suffix_is_not_bass() {
        let ch = c("C6/9");
        assert_eq!(ch.suffix, "6/9");
        assert_eq!(ch.bass, None);
    }

    #[test]
    fn rejects_non_chords() {
        assert!("Hello".parse::<Chord>().is_err());
        assert!("".parse::<Chord>().is_err());
        assert!("A m".parse::<Chord>().is_err());
    }

    #[test]
    fn transposes_keeping_style() {
        assert_eq!(transpose_name("G/B", 2), "A/C#");
        assert_eq!(transpose_name("Bb", 2), "C");
        assert_eq!(transpose_name("Eb", 1), "E");
        assert_eq!(transpose_name("Db", 1), "D");
        assert_eq!(transpose_name("Ab", 1), "A");
        assert_eq!(transpose_name("Bb", -1), "A");
        assert_eq!(transpose_name("Gb", 1), "G");
        assert_eq!(transpose_name("Eb", -2), "Db");
        assert_eq!(transpose_name("C#m7(b5)", -1), "Cm7(b5)");
        assert_eq!(transpose_name("E", 12), "E");
        assert_eq!(transpose_name("E", -13), "D#");
        assert_eq!(transpose_name("não é acorde", 3), "não é acorde");
    }

    #[test]
    fn roundtrips_display() {
        for name in ["C", "Am7", "F#m7(b5)", "Bb/D", "Gsus4", "D7(9)", "E/G#"] {
            assert_eq!(c(name).to_string(), name);
        }
    }
}
