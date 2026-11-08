//! Leitura de texto de prints (cifra de site, frame de vídeo com tab), sem
//! internet: usa o Tesseract instalado no computador e arruma os erros mais
//! comuns que ele comete em cifras e tabs.

use std::process::Command;

pub const INSTALL_HINT: &str =
    "Para ler prints, instale o leitor de texto: sudo dnf install tesseract tesseract-langpack-por";

/// Lê o texto da imagem. `Err` traz uma mensagem para mostrar na tela.
pub fn read_image(path: &str) -> Result<String, String> {
    let langs = match Command::new("tesseract").arg("--list-langs").output() {
        Ok(out) => {
            let list = String::from_utf8_lossy(&out.stdout).to_string()
                + &String::from_utf8_lossy(&out.stderr);
            let has = |l: &str| list.lines().any(|x| x.trim() == l);
            match (has("por"), has("eng")) {
                (true, true) => "por+eng",
                (true, false) => "por",
                _ => "eng",
            }
        }
        Err(_) => return Err(INSTALL_HINT.into()),
    };
    // --psm 6: um bloco de texto uniforme, que mantém as linhas da cifra/tab.
    let out = Command::new("tesseract")
        .args([path, "stdout", "-l", langs, "--psm", "6"])
        .output()
        .map_err(|_| INSTALL_HINT.to_string())?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(format!("Não consegui ler a imagem: {}", err.trim()));
    }
    Ok(clean(&String::from_utf8_lossy(&out.stdout)))
}

/// Prepara um print em tons de cinza para o OCR: deixa texto escuro em fundo
/// claro (frames de vídeo costumam ser o contrário) e separa texto do fundo
/// com um limiar automático (método de Otsu). Devolve os pixels em 0 ou 255.
pub fn binarize(gray: &[u8]) -> Vec<u8> {
    if gray.is_empty() {
        return Vec::new();
    }
    let mut hist = [0u64; 256];
    for &g in gray {
        hist[g as usize] += 1;
    }
    let total = gray.len() as f64;
    let sum: f64 = hist
        .iter()
        .enumerate()
        .map(|(i, &n)| i as f64 * n as f64)
        .sum();
    let (mut sum_b, mut w_b, mut best, mut threshold) = (0f64, 0f64, -1f64, 128u8);
    for (t, &n) in hist.iter().enumerate() {
        w_b += n as f64;
        if w_b == 0.0 {
            continue;
        }
        let w_f = total - w_b;
        if w_f == 0.0 {
            break;
        }
        sum_b += t as f64 * n as f64;
        let m_b = sum_b / w_b;
        let m_f = (sum - sum_b) / w_f;
        let between = w_b * w_f * (m_b - m_f) * (m_b - m_f);
        if between > best {
            best = between;
            threshold = t as u8;
        }
    }
    // A maior parte da imagem é fundo: se o fundo é escuro, inverte.
    let dark_pixels = gray.iter().filter(|&&g| g <= threshold).count();
    let dark_background = dark_pixels * 2 > gray.len();
    gray.iter()
        .map(|&g| {
            let ink = if dark_background {
                g > threshold
            } else {
                g <= threshold
            };
            if ink {
                0
            } else {
                255
            }
        })
        .collect()
}

/// Imagem PGM (cinza) simples, que o Tesseract lê direto.
pub fn pgm(width: u32, height: u32, pixels: &[u8]) -> Vec<u8> {
    let mut out = format!("P5\n{width} {height}\n255\n").into_bytes();
    out.extend_from_slice(pixels);
    out
}

/// Conserta o que o OCR costuma errar em tabs e cifras:
/// "G l---8--" -> "G|---8--", travessões viram hífens, "O" vira "0" dentro da tab.
pub fn clean(text: &str) -> String {
    let mut out = Vec::new();
    for raw in text.lines() {
        let line = raw
            .replace(['—', '–', '_', '−'], "-")
            .replace('¦', "|")
            .trim_end()
            .to_string();
        let line = fix_tab_line(&line).unwrap_or(line);
        out.push(fix_chord_case(&line).unwrap_or(line));
    }
    // Sem linhas em branco sobrando no fim.
    while out.last().is_some_and(|l| l.trim().is_empty()) {
        out.pop();
    }
    out.join("\n")
}

/// Linha de acordes em que o OCR leu uma letra minúscula ("c G" -> "C G").
/// Só mexe se a linha já tem um acorde certo e todas as palavras viram acordes.
fn fix_chord_case(line: &str) -> Option<String> {
    let tokens: Vec<&str> = line.split_whitespace().collect();
    if tokens.is_empty() || !tokens.iter().any(|t| crate::sheet::is_chord_token(t)) {
        return None;
    }
    let mut changed = false;
    let mut fixed = Vec::new();
    for t in &tokens {
        if crate::sheet::is_chord_token(t) {
            fixed.push(t.to_string());
            continue;
        }
        let mut c = t.chars();
        let first = c.next()?;
        if !('a'..='g').contains(&first) {
            return None;
        }
        let up = first.to_ascii_uppercase().to_string() + c.as_str();
        if !crate::sheet::is_chord_token(&up) {
            return None;
        }
        fixed.push(up);
        changed = true;
    }
    if !changed {
        return None;
    }
    // Mantém os espaços originais trocando palavra por palavra.
    let mut out = line.to_string();
    for (t, f) in tokens.iter().zip(&fixed) {
        if t != f {
            out = out.replacen(t, f, 1);
        }
    }
    Some(out)
}

fn fix_tab_line(line: &str) -> Option<String> {
    let t = line.trim_start();
    let mut chars = t.chars();
    let letter = chars.next()?;
    if !"EADGBe".contains(letter) {
        return None;
    }
    let rest = chars.as_str().trim_start();
    let sep = rest.chars().next()?;
    if !"|lI![]:".contains(sep) {
        return None;
    }
    let body = &rest[sep.len_utf8()..];
    // Só é tab se o resto é quase todo traço, número e barra.
    let total = body.chars().filter(|c| !c.is_whitespace()).count();
    let tabby = body
        .chars()
        .filter(|c| c.is_ascii_digit() || "-|/\\hpbx~O".contains(*c))
        .count();
    if total < 4 || tabby * 10 < total * 8 || !body.contains('-') {
        return None;
    }
    let body: String = body
        .chars()
        .filter(|c| !c.is_whitespace())
        .map(|c| match c {
            'O' | 'o' => '0',
            'l' | 'I' | '!' => '|',
            other => other,
        })
        .collect();
    Some(format!("{letter}|{body}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binarize_inverts_dark_background() {
        // Fundo escuro (10) com "texto" claro (200): vira texto preto em fundo branco.
        let img = [10, 10, 10, 200, 10, 10];
        assert_eq!(binarize(&img), [255, 255, 255, 0, 255, 255]);
        let img = [240, 240, 30, 240];
        assert_eq!(binarize(&img), [255, 255, 0, 255]);
        assert_eq!(&pgm(2, 1, &[0, 255])[..7], b"P5\n2 1\n");
    }

    #[test]
    fn fixes_common_ocr_mistakes() {
        let raw = "E l-------------|\nG|---8—6-5-- \nD !--6-----1O--\n[Intro] Am  F\n\n";
        assert_eq!(
            clean(raw),
            "E|-------------|\nG|---8-6-5--\nD|--6-----10--\n[Intro] Am  F"
        );
        assert_eq!(clean("c             G"), "C             G");
        assert_eq!(clean("e a casa"), "e a casa");
        // Letra que começa com E não vira tab.
        assert_eq!(clean("E la vem ela"), "E la vem ela");
    }
}
