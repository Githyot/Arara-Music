//! Leitura de tablatura em texto (o formato de sites e aulas):
//!
//! ```text
//! e|-----------------|
//! B|-----------------|
//! G|------8--6-5-----|
//! D|----6------------|
//! A|-8-8-------------|
//! E|-----------------|
//! ```
//!
//! Cada coluna com número vira um evento (uma nota, ou várias tocadas juntas);
//! `|` no meio da linha vira barra de compasso. Números de dois dígitos
//! (`10`, `12`) contam como uma nota só. Técnicas (`h`, `p`, `/`, `\`, `b`, `~`)
//! ficam guardadas na nota seguinte para a interface mostrar.

use serde::{Deserialize, Serialize};

/// Casa especial para corda abafada ("x" na tab).
pub const MUTED: u8 = 255;

impl TabNote {
    /// Como a nota aparece na tab: técnica + casa, ou "x" se abafada.
    pub fn label(&self) -> String {
        if self.fret == MUTED {
            format!("{}x", self.tech)
        } else {
            format!("{}{}", self.tech, self.fret)
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TabNote {
    /// Corda: 0 = Mi grave ... 5 = Mi agudo.
    pub string: u8,
    pub fret: u8,
    /// Técnica que liga a nota anterior a esta ("h", "p", "/", "\\", "b", "~"), ou vazio.
    #[serde(skip_serializing_if = "String::is_empty", default)]
    pub tech: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(untagged)]
pub enum TabEvent {
    Notes { notes: Vec<TabNote> },
    Bar { bar: bool },
}

/// Lê todo o texto (pode ter vários blocos de 6 linhas) e devolve os eventos em ordem.
pub fn parse(text: &str) -> Vec<TabEvent> {
    let mut out: Vec<TabEvent> = Vec::new();
    let mut block: Vec<(Option<char>, &str)> = Vec::new();
    for raw in text.lines() {
        match split_line(raw) {
            Some(line) => block.push(line),
            None => {
                flush(&mut block, &mut out);
            }
        }
    }
    flush(&mut block, &mut out);
    // Sem barras sobrando nas pontas.
    while matches!(out.last(), Some(TabEvent::Bar { .. })) {
        out.pop();
    }
    while matches!(out.first(), Some(TabEvent::Bar { .. })) {
        out.remove(0);
    }
    out
}

pub fn parse_json(text: &str) -> String {
    serde_json::to_string(&parse(text)).unwrap_or_else(|_| "[]".into())
}

/// "e|--3--|" -> (Some('e'), "--3--|"). Linhas sem "|" depois de uma letra de corda não são tab.
fn split_line(raw: &str) -> Option<(Option<char>, &str)> {
    let line = raw.trim();
    let bar = line.find('|')?;
    let label = line[..bar].trim();
    let letter = match label.chars().count() {
        0 => None,
        1 => {
            let c = label.chars().next().unwrap();
            if !"EADGBeadgb".contains(c) {
                return None;
            }
            Some(c)
        }
        _ => return None,
    };
    let body = &line[bar + 1..];
    if !body.contains('-') {
        return None;
    }
    Some((letter, body))
}

fn string_index(letter: Option<char>, line: usize, lines: usize) -> Option<u8> {
    if lines == 6 {
        // Bloco completo: de cima para baixo é Mi agudo ... Mi grave.
        return Some(5 - line as u8);
    }
    Some(match letter? {
        'e' => 5,
        'B' | 'b' => 4,
        'G' | 'g' => 3,
        'D' | 'd' => 2,
        'A' | 'a' => 1,
        'E' => {
            if line == 0 {
                5
            } else {
                0
            }
        }
        _ => return None,
    })
}

fn flush(block: &mut Vec<(Option<char>, &str)>, out: &mut Vec<TabEvent>) {
    if block.is_empty() {
        return;
    }
    let lines = block.len().min(6);
    // Coluna -> notas que começam nela; colunas com barra em alguma linha.
    let width = block
        .iter()
        .map(|(_, b)| b.chars().count())
        .max()
        .unwrap_or(0);
    let mut columns: Vec<Vec<TabNote>> = vec![Vec::new(); width];
    let mut bars = vec![false; width];

    for (i, (letter, body)) in block.iter().take(6).enumerate() {
        let Some(string) = string_index(*letter, i, lines) else {
            continue;
        };
        let chars: Vec<char> = body.chars().collect();
        let mut c = 0;
        let mut tech = String::new();
        while c < chars.len() {
            let ch = chars[c];
            if ch.is_ascii_digit() {
                let start = c;
                let mut n = 0u32;
                while c < chars.len() && chars[c].is_ascii_digit() && c - start < 2 {
                    n = n * 10 + chars[c].to_digit(10).unwrap();
                    c += 1;
                }
                if n <= 24 {
                    columns[start].push(TabNote {
                        string,
                        fret: n as u8,
                        tech: std::mem::take(&mut tech),
                    });
                }
                continue;
            }
            match ch {
                '|' => {
                    // A barra final da linha não conta como compasso no meio.
                    if c + 1 < chars.len() {
                        bars[c] = true;
                    }
                }
                'x' | 'X' => columns[c].push(TabNote {
                    string,
                    fret: MUTED,
                    tech: std::mem::take(&mut tech),
                }),
                'h' | 'p' | '/' | '\\' | 'b' | '~' => tech = ch.to_string(),
                '-' | ' ' => {}
                _ => {}
            }
            c += 1;
        }
    }

    if !out.is_empty() && !matches!(out.last(), Some(TabEvent::Bar { .. })) {
        out.push(TabEvent::Bar { bar: true });
    }
    for c in 0..width {
        if bars[c] {
            if !matches!(out.last(), Some(TabEvent::Bar { .. })) && !out.is_empty() {
                out.push(TabEvent::Bar { bar: true });
            }
        } else if !columns[c].is_empty() {
            let mut notes = std::mem::take(&mut columns[c]);
            notes.sort_by_key(|n| n.string);
            out.push(TabEvent::Notes { notes });
        }
    }
    block.clear();
}

/// Um bloco da tab para a visualização de aula: notas com a coluna onde
/// aparecem, o acorde escrito em cima e a seta de batida embaixo de cada nota.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct System {
    /// Largura do bloco, em colunas de texto.
    pub width: usize,
    pub chords: Vec<LessonChord>,
    pub events: Vec<LessonEvent>,
    /// Colunas com barra de compasso no meio da linha.
    pub bars: Vec<usize>,
    /// Quantas setas a linha de setas tinha (para avisar se não bate com os toques).
    pub arrows: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LessonChord {
    pub col: usize,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LessonEvent {
    pub col: usize,
    pub notes: Vec<TabNote>,
    /// "D" (para baixo), "U" (para cima), "X"/"XU" (abafada, para baixo ou
    /// para cima) ou vazio.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub arrow: String,
}

/// Caractere da seta na linha de setas da tab: ↓ ↑, e ⇓ ⇑ para a batida
/// abafada (no app aparecem como ↓× e ↑×) e ⬇ ⬆ para a palhetada forte
/// (acento, código com ">" no fim: "D>", "U>").
fn arrow_char(arrow: &str) -> char {
    match arrow {
        "U" => '↑',
        "U>" | "XU>" => '⬆',
        "D>" | "X>" => '⬇',
        "X" => '⇓',
        "XU" => '⇑',
        _ => '↓',
    }
}

pub fn lesson(text: &str) -> Vec<System> {
    let mut out = Vec::new();
    let mut block: Vec<&str> = Vec::new();
    for line in text.lines().chain(std::iter::once("")) {
        if line.trim().is_empty() {
            if let Some(sys) = lesson_block(&block) {
                out.push(sys);
            }
            block.clear();
        } else {
            block.push(line);
        }
    }
    out
}

/// Liga cada seta a uma nota, na ordem, com a menor distância total entre as
/// colunas. Quem escreve a linha de setas à mão costuma deixá-la escorregar
/// algumas colunas, então a ordem vale mais que a coluna exata.
/// Devolve pares (índice da seta, índice da nota).
fn align(arrows: &[usize], notes: &[usize]) -> Vec<(usize, usize)> {
    // Mesma quantidade de setas e de toques: a 1ª seta é do 1º toque, a 2ª do
    // 2º, e assim por diante.
    if arrows.len() == notes.len() {
        return (0..arrows.len()).map(|i| (i, i)).collect();
    }
    const SKIP_ARROW: usize = 40;
    let (m, n) = (arrows.len(), notes.len());
    // cost[i][j]: as i primeiras setas com as j primeiras notas.
    let mut cost = vec![vec![usize::MAX / 2; n + 1]; m + 1];
    let mut how = vec![vec![0u8; n + 1]; m + 1];
    for j in 0..=n {
        cost[0][j] = 0;
        how[0][j] = 2;
    }
    for i in 1..=m {
        for j in 0..=n {
            let mut best = (cost[i - 1][j] + SKIP_ARROW, 1u8);
            if j > 0 {
                if cost[i][j - 1] < best.0 {
                    best = (cost[i][j - 1], 2);
                }
                let d = arrows[i - 1].abs_diff(notes[j - 1]);
                if cost[i - 1][j - 1] + d <= best.0 {
                    best = (cost[i - 1][j - 1] + d, 3);
                }
            }
            cost[i][j] = best.0;
            how[i][j] = best.1;
        }
    }
    let (mut i, mut j) = (m, n);
    let mut out = Vec::new();
    while i > 0 {
        match how[i][j] {
            1 => i -= 1,
            2 => j -= 1,
            _ => {
                out.push((i - 1, j - 1));
                i -= 1;
                j -= 1;
            }
        }
    }
    out.reverse();
    out
}

/// Blocos da tab (separados por linha em branco) e, para os que têm tab, o
/// sistema lido.
fn blocks(text: &str) -> Vec<(Vec<&str>, Option<System>)> {
    let mut out = Vec::new();
    let mut block: Vec<&str> = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() {
            if !block.is_empty() {
                let sys = lesson_block(&block);
                out.push((std::mem::take(&mut block), sys));
            }
            out.push((vec![line], None));
        } else {
            block.push(line);
        }
    }
    if !block.is_empty() {
        let sys = lesson_block(&block);
        out.push((block, sys));
    }
    out
}

/// Reescreve a linha de setas de um bloco com cada seta embaixo da sua nota.
fn rewrite_block(block: &[&str], sys: &System) -> Vec<String> {
    let Some(first_tab) = block.iter().position(|l| split_line(l).is_some()) else {
        return block.iter().map(|l| l.to_string()).collect();
    };
    let last_tab = block
        .iter()
        .rposition(|l| split_line(l).is_some())
        .unwrap_or(first_tab);
    let lead = block[first_tab].len() - block[first_tab].trim_start().len();
    let offset = block[first_tab].trim_start().find('|').unwrap_or(0) + 1 + lead;
    let has = sys.events.iter().any(|e| !e.arrow.is_empty());
    let mut line: Vec<char> = Vec::new();
    for e in &sys.events {
        if e.arrow.is_empty() {
            continue;
        }
        // Embaixo do último algarismo da nota mais grave (onde o olho bate).
        let len = e.notes.first().map(|n| n.label().len()).unwrap_or(1);
        let at = offset + e.col + len - 1;
        if line.len() <= at {
            line.resize(at + 1, ' ');
        }
        line[at] = arrow_char(&e.arrow);
    }
    let mut out = Vec::new();
    let mut placed = false;
    for (i, l) in block.iter().enumerate() {
        if i > last_tab && crate::sheet::is_arrow_line(l) {
            if has && !placed {
                out.push(line.iter().collect());
                placed = true;
            }
            continue;
        }
        out.push(l.to_string());
        if i == last_tab
            && has
            && !block[last_tab + 1..]
                .iter()
                .any(|l| crate::sheet::is_arrow_line(l))
        {
            out.push(line.iter().collect());
            placed = true;
        }
    }
    out
}

fn rebuild(text: &str, change: impl Fn(usize, &mut System)) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut n = 0;
    for (block, sys) in blocks(text) {
        match sys {
            Some(mut sys) => {
                change(n, &mut sys);
                n += 1;
                out.extend(rewrite_block(&block, &sys));
            }
            None => out.extend(block.iter().map(|l| l.to_string())),
        }
    }
    let mut s = out.join("\n");
    if text.ends_with('\n') {
        s.push('\n');
    }
    s
}

/// A tab com cada seta embaixo da nota que ela marca.
pub fn align_arrows(text: &str) -> String {
    rebuild(text, |_, _| {})
}

/// Põe ("D"/"U") ou tira ("") a seta de uma nota (sistema e nota contados
/// como em `lesson`).
pub fn set_arrow(text: &str, system: usize, event: usize, arrow: &str) -> String {
    rebuild(text, |n, sys| {
        if n == system {
            if let Some(e) = sys.events.get_mut(event) {
                e.arrow = arrow.to_string();
            }
        }
    })
}

// ---- Editor visual ----
// O editor mexe numa lista de toques (sem colunas de texto) e o texto da tab
// é gerado de novo a cada mudança, sempre alinhado.

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EditChord {
    /// Índice do toque onde o acorde começa.
    pub at: usize,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EditEvent {
    pub notes: Vec<TabNote>,
    #[serde(default)]
    pub arrow: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EditSystem {
    #[serde(default)]
    pub chords: Vec<EditChord>,
    #[serde(default)]
    pub events: Vec<EditEvent>,
    /// Barra de compasso antes destes toques.
    #[serde(default)]
    pub bars: Vec<usize>,
}

pub fn edit_model(text: &str) -> Vec<EditSystem> {
    lesson(text)
        .into_iter()
        .map(|sys| {
            let first_at = |col: usize| {
                sys.events
                    .iter()
                    .position(|e| e.col + 1 >= col)
                    .unwrap_or(sys.events.len().saturating_sub(1))
            };
            let mut chords: Vec<EditChord> = Vec::new();
            for c in &sys.chords {
                let at = first_at(c.col);
                if !chords.iter().any(|x| x.at == at) {
                    chords.push(EditChord {
                        at,
                        name: c.name.clone(),
                    });
                }
            }
            let mut bars: Vec<usize> = sys
                .bars
                .iter()
                .filter_map(|&b| sys.events.iter().position(|e| e.col > b))
                .filter(|&i| i > 0)
                .collect();
            bars.dedup();
            EditSystem {
                chords,
                events: sys
                    .events
                    .iter()
                    .map(|e| EditEvent {
                        notes: e.notes.clone(),
                        arrow: e.arrow.clone(),
                    })
                    .collect(),
                bars,
            }
        })
        .collect()
}

pub fn edit_model_json(text: &str) -> String {
    serde_json::to_string(&edit_model(text)).unwrap_or_else(|_| "[]".into())
}

/// Escreve a tab em texto a partir dos toques: acordes em cima, seis linhas
/// (e B G D A E) e a linha de setas embaixo, cada seta sob o seu toque.
pub fn render(systems: &[EditSystem]) -> String {
    const NAMES: [&str; 6] = ["e", "B", "G", "D", "A", "E"];
    let mut out: Vec<String> = Vec::new();
    for (si, sys) in systems.iter().enumerate() {
        if si > 0 {
            out.push(String::new());
        }
        let mut lines: Vec<String> = NAMES.iter().map(|n| format!("{n}|--")).collect();
        let mut chord_line: Vec<char> = Vec::new();
        let mut arrow_line: Vec<char> = Vec::new();
        let mut pos = 2usize; // coluna no corpo da tab (depois do "|")
        let put = |line: &mut Vec<char>, at: usize, text: &str| {
            let at = at.max(if line.is_empty() { 0 } else { line.len() + 1 });
            if line.len() < at {
                line.resize(at, ' ');
            }
            line.extend(text.chars());
        };
        for (i, ev) in sys.events.iter().enumerate() {
            if i > 0 && sys.bars.contains(&i) {
                for l in lines.iter_mut() {
                    l.push_str("|--");
                }
                pos += 3;
            }
            let token = |n: &TabNote| n.label();
            // Slide de uma nota só para outra na mesma corda: fica colado, como
            // se escreve à mão ("8/10", "10\\8"), sem traços no meio.
            let slide = i > 0
                && !sys.bars.contains(&i)
                && ev.notes.len() == 1
                && (ev.notes[0].tech == "/" || ev.notes[0].tech == "\\")
                && sys.events[i - 1].notes.len() == 1
                && sys.events[i - 1].notes[0].string == ev.notes[0].string
                && sys.events[i - 1].notes[0].fret != MUTED;
            if slide && lines.iter().all(|l| l.ends_with("---")) {
                for l in lines.iter_mut() {
                    l.truncate(l.len() - 3);
                }
                pos -= 3;
            }
            let w = ev
                .notes
                .iter()
                .map(|n| token(n).chars().count())
                .max()
                .unwrap_or(1);
            if let Some(c) = sys.chords.iter().find(|c| c.at == i) {
                put(&mut chord_line, 2 + pos, &c.name);
            }
            for (li, l) in lines.iter_mut().enumerate() {
                let string = 5 - li as u8;
                let t = ev
                    .notes
                    .iter()
                    .find(|n| n.string == string)
                    .map(token)
                    .unwrap_or_default();
                l.push_str(&t);
                l.push_str(&"-".repeat(w - t.chars().count() + 3));
            }
            // Toque sem nota é pausa: não leva seta (senão a contagem desanda).
            if !ev.arrow.is_empty() && !ev.notes.is_empty() {
                let low = ev.notes.iter().min_by_key(|n| n.string);
                let len = low.map(|n| token(n).chars().count()).unwrap_or(1);
                let at = 2 + pos + len - 1;
                if arrow_line.len() <= at {
                    arrow_line.resize(at + 1, ' ');
                }
                arrow_line[at] = arrow_char(&ev.arrow);
            }
            pos += w + 3;
        }
        for l in lines.iter_mut() {
            l.push('|');
        }
        if !chord_line.is_empty() {
            out.push(chord_line.iter().collect());
        }
        out.extend(lines);
        if !arrow_line.is_empty() {
            out.push(arrow_line.iter().collect());
        }
    }
    out.join("\n")
}

pub fn render_json(json: &str) -> String {
    serde_json::from_str::<Vec<EditSystem>>(json)
        .map(|s| render(&s))
        .unwrap_or_default()
}

pub fn lesson_json(text: &str) -> String {
    serde_json::to_string(&lesson(text)).unwrap_or_else(|_| "[]".into())
}

fn lesson_block(block: &[&str]) -> Option<System> {
    let first_tab = block.iter().position(|l| split_line(l).is_some())?;
    let tab_lines: Vec<(Option<char>, &str)> = block.iter().filter_map(|l| split_line(l)).collect();
    // Onde começa o corpo da tab ("E|" = 2 colunas), para alinhar acordes e setas.
    let offset = block[first_tab].trim_start().find('|')?
        + 1
        + (block[first_tab].len() - block[first_tab].trim_start().len());
    let lines = tab_lines.len().min(6);
    let width = tab_lines
        .iter()
        .map(|(_, b)| b.chars().count())
        .max()
        .unwrap_or(0);
    let mut columns: Vec<Vec<TabNote>> = vec![Vec::new(); width];
    let mut bars = Vec::new();
    for (i, (letter, body)) in tab_lines.iter().take(6).enumerate() {
        let Some(string) = string_index(*letter, i, lines) else {
            continue;
        };
        let chars: Vec<char> = body.chars().collect();
        let mut c = 0;
        let mut tech = String::new();
        while c < chars.len() {
            let ch = chars[c];
            if ch.is_ascii_digit() {
                let start = c;
                let mut n = 0u32;
                while c < chars.len() && chars[c].is_ascii_digit() && c - start < 2 {
                    n = n * 10 + chars[c].to_digit(10).unwrap();
                    c += 1;
                }
                if n <= 24 {
                    columns[start].push(TabNote {
                        string,
                        fret: n as u8,
                        tech: std::mem::take(&mut tech),
                    });
                }
                continue;
            }
            match ch {
                '|' if c + 1 < chars.len() && c > 0 && !bars.contains(&c) => bars.push(c),
                'x' | 'X' => columns[c].push(TabNote {
                    string,
                    fret: MUTED,
                    tech: std::mem::take(&mut tech),
                }),
                'h' | 'p' | '/' | '\\' | 'b' | '~' => tech = ch.to_string(),
                _ => {}
            }
            c += 1;
        }
    }
    // Notas de duas casas em cordas diferentes que começam uma coluna depois
    // ("12" em cima de "3") ficam no mesmo evento.
    let mut events: Vec<LessonEvent> = Vec::new();
    for (col, notes) in columns.into_iter().enumerate() {
        if notes.is_empty() {
            continue;
        }
        match events.last_mut() {
            Some(last)
                if col == last.col + 1
                    && !notes
                        .iter()
                        .any(|n| last.notes.iter().any(|m| m.string == n.string)) =>
            {
                last.notes.extend(notes);
            }
            _ => events.push(LessonEvent {
                col,
                notes,
                arrow: String::new(),
            }),
        }
    }
    for e in &mut events {
        e.notes.sort_by_key(|n| n.string);
    }
    bars.sort();

    let body_col = |i: usize| i.checked_sub(offset);
    let mut chords = Vec::new();
    for line in &block[..first_tab] {
        if crate::sheet::chord_line(line.trim()).is_none() {
            continue;
        }
        let chars: Vec<char> = line.chars().collect();
        let mut i = 0;
        while i < chars.len() {
            if chars[i].is_whitespace() {
                i += 1;
                continue;
            }
            let start = i;
            while i < chars.len() && !chars[i].is_whitespace() {
                i += 1;
            }
            let word: String = chars[start..i].iter().collect();
            if crate::sheet::is_chord_token(&word) {
                chords.push(LessonChord {
                    col: body_col(start).unwrap_or(0),
                    name: word,
                });
            }
        }
    }
    let last_tab = block.iter().rposition(|l| split_line(l).is_some())?;
    let mut arrows: Vec<(usize, &'static str)> = Vec::new();
    for line in &block[last_tab + 1..] {
        if !crate::sheet::is_arrow_line(line) {
            continue;
        }
        for (i, ch) in line.chars().enumerate() {
            let arrow = match ch {
                '↓' | '⇣' => "D",
                '↑' | '⇡' => "U",
                '⇓' => "X",
                '⇑' => "XU",
                '⬇' => "D>",
                '⬆' => "U>",
                _ => continue,
            };
            if let Some(col) = body_col(i) {
                arrows.push((col, arrow));
            }
        }
    }
    let arrow_count = arrows.len();
    let cols: Vec<usize> = events.iter().map(|e| e.col).collect();
    for (a, e) in align(&arrows.iter().map(|a| a.0).collect::<Vec<_>>(), &cols) {
        events[e].arrow = arrows[a].1.into();
    }
    Some(System {
        width,
        chords,
        events,
        bars,
        arrows: arrow_count,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frets(ev: &[TabEvent]) -> Vec<String> {
        ev.iter()
            .map(|e| match e {
                TabEvent::Bar { .. } => "|".to_string(),
                TabEvent::Notes { notes } => notes
                    .iter()
                    .map(|n| format!("{}:{}", n.string, n.label()))
                    .collect::<Vec<_>>()
                    .join("+"),
            })
            .collect()
    }

    #[test]
    fn reads_single_notes_and_two_digit_frets() {
        let t = "\
E|-----------------------|
B|-----------------------|
G|------8--6-5-----------|
D|----6---------8/10-----|
A|-8-8-------------------|
E|-----------------------|";
        let ev = parse(t);
        assert_eq!(
            frets(&ev),
            ["1:8", "1:8", "2:6", "3:8", "3:6", "3:5", "2:8", "2:/10"]
        );
    }

    #[test]
    fn slides_stay_glued_when_rendered() {
        let text = "e|--------|\nB|--8/10--|\nG|--------|\nD|--------|\nA|--------|\nE|--------|";
        let m = edit_model(text);
        let ev = &m[0].events;
        assert_eq!(ev.len(), 2);
        assert_eq!(ev[1].notes[0].tech, "/");
        let out = render(&m);
        assert!(out.contains("8/10"), "{out}");
        let back = edit_model(&out);
        assert_eq!(back, m);
        // Descendo.
        let down = text.replace("8/10", "10\\8-");
        let out = render(&edit_model(&down));
        assert!(out.contains("10\\8"), "{out}");
    }

    #[test]
    fn accented_arrows_round_trip() {
        let text = "e|-0-0-|\nB|-1-1-|\n  ⬇ ↑";
        let sys = &edit_model(text)[0];
        assert_eq!(sys.events[0].arrow, "D>");
        assert_eq!(sys.events[1].arrow, "U");
        assert!(set_arrow(text, 0, 1, "U>").contains('⬆'));
    }

    #[test]
    fn muted_arrows_round_trip() {
        let tab = "e|--0--0--|\nB|--1--1--|\nG|--0--0--|\nD|--2--2--|\nA|--3--3--|\nE|-----x--|\n    ⇓  ⇑\n";
        let sys = &lesson(tab)[0];
        assert_eq!(sys.events[0].arrow, "X");
        assert_eq!(sys.events[1].arrow, "XU");
        let m = edit_model(tab);
        let again = &lesson(&render(&m))[0];
        assert_eq!(again.events[1].arrow, "XU");
    }

    #[test]
    fn arrows_follow_notes_in_order_even_when_they_drift() {
        let tab = concat!(
            "E|------------------|\n",
            "B|------------------|\n",
            "G|----12---12-------|\n",
            "D|----13---13-------|\n",
            "A|------------------|\n",
            "E|--0----0----11----|\n",
            "    ↓  ↑  ↓ ↑  ↓\n",
        );
        let sys = &lesson(tab)[0];
        let arrows: Vec<&str> = sys.events.iter().map(|e| e.arrow.as_str()).collect();
        assert_eq!(arrows, ["D", "U", "D", "U", "D"]);
        let fixed = align_arrows(tab);
        assert_eq!(fixed.lines().last().unwrap(), "    ↓  ↑ ↓  ↑  ↓");
        let changed = set_arrow(tab, 0, 1, "");
        let sys = &lesson(&changed)[0];
        assert_eq!(sys.events[1].arrow, "");
        assert_eq!(sys.events[2].arrow, "D");
    }

    #[test]
    fn edit_model_round_trips_through_render() {
        let tab = concat!(
            "   Am      F\n",
            "E|------------------|\n",
            "B|------------------|\n",
            "G|----12---12-------|\n",
            "D|----13---13-------|\n",
            "A|------------------|\n",
            "E|--0----0----11----|\n",
            "    ↓  ↑  ↓ ↑  ↓\n",
        );
        let model = edit_model(tab);
        assert_eq!(model[0].events.len(), 5);
        assert_eq!(
            model[0].chords[0],
            EditChord {
                at: 0,
                name: "Am".into()
            }
        );
        assert_eq!(model[0].chords[1].name, "F");
        let text = render(&model);
        let again = edit_model(&text);
        assert_eq!(again, model, "{text}");
    }

    #[test]
    fn muted_strings_survive_as_x() {
        let tab = "e|--x--3--|\nB|--x--3--|\nG|--x--0--|\nD|--x--0--|\nA|--x--2--|\nE|--x--3--|\n    ↓  ↑\n";
        let model = edit_model(tab);
        assert_eq!(model[0].events.len(), 2);
        assert!(model[0].events[0].notes.iter().all(|n| n.fret == MUTED));
        let text = render(&model);
        assert!(text.lines().next().unwrap().contains('x'), "{text}");
        assert_eq!(edit_model(&text), model);
    }

    #[test]
    fn lesson_blocks_with_chords_and_arrows() {
        let t = concat!(
            "   Em7(9)     D\n",
            "E|------------|\n",
            "B|------------|\n",
            "G|----12------|\n",
            "D|----13------|\n",
            "A|------------|\n",
            "E|--0-----11--|\n",
            "    ↓ ↑   ↓\n",
            "\n",
            "   Bm\n",
            "E|--2--|"
        );
        let l = lesson(t);
        assert_eq!(l.len(), 2);
        let a = &l[0];
        assert_eq!(
            a.chords[0],
            LessonChord {
                col: 1,
                name: "Em7(9)".into()
            }
        );
        assert_eq!(a.chords[1].name, "D");
        assert_eq!(a.events.len(), 3);
        assert_eq!((a.events[0].col, a.events[0].arrow.as_str()), (2, "D"));
        assert_eq!(a.events[1].notes.len(), 2);
        assert_eq!(a.events[1].arrow, "U");
        assert_eq!(a.events[2].arrow, "D");
        assert_eq!(l[1].events[0].notes[0].fret, 2);
    }

    #[test]
    fn chords_bars_and_blocks() {
        let t = "\
e|--0--|--3--|
B|--1--|--0--|
G|--0--|--0--|
D|--2--|--0--|
A|--3--|--2--|
E|-----|--3--|

e|-5-|
B|---|
G|---|
D|---|
A|---|
E|---|";
        let ev = parse(t);
        assert_eq!(
            frets(&ev),
            [
                "1:3+2:2+3:0+4:1+5:0",
                "|",
                "0:3+1:2+2:0+3:0+4:0+5:3",
                "|",
                "5:5"
            ]
        );
        assert!(parse("Uma linha de letra\nE outra").is_empty());
        assert_eq!(
            parse_json("e|-3-|\nB|---|\nG|---|\nD|---|\nA|---|\nE|---|"),
            r#"[{"notes":[{"string":5,"fret":3}]}]"#
        );
    }
}
