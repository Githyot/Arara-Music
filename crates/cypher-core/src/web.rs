//! Importar cifra de um link: o app baixa a página (o usuário colou o
//! endereço) e daqui sai só o texto da cifra, que passa pelo mesmo leitor do
//! texto colado. Nada é guardado além do que o usuário salvar na biblioteca.

use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Default)]
pub struct Page {
    pub title: String,
    pub artist: String,
    /// Tom escrito na página ("Tom: G"), se houver.
    pub key: String,
    /// Casa do capotraste ("Capotraste na 2ª casa"), 0 se não houver.
    pub capo: u32,
    /// Andamento ("120 bpm"), 0 se não houver.
    pub bpm: u32,
    /// Texto da cifra, com as quebras de linha da página.
    pub text: String,
}

/// Tira título, artista e o texto da cifra do HTML.
/// Sites de cifra costumam pôr a cifra num `<pre>`; sem `<pre>`, usa o corpo todo.
pub fn extract(html: &str) -> Page {
    let (title, artist) = title_artist(html);
    let pres = blocks(html, "pre");
    let raw = if pres.is_empty() {
        let body = blocks(html, "body").into_iter().next().unwrap_or(html);
        to_text(&strip_blocks(&strip_blocks(body, "script"), "style"), true)
    } else {
        // A maior <pre> é a cifra (outras podem ser trechos de código, etc.).
        let best = pres.iter().max_by_key(|p| p.len()).copied().unwrap_or("");
        to_text(best, false)
    };
    let text = raw
        .lines()
        .map(str::trim_end)
        .collect::<Vec<_>>()
        .join("\n")
        .trim_matches('\n')
        .to_string();
    let plain = to_text(&strip_blocks(&strip_blocks(html, "script"), "style"), true);
    Page {
        title,
        artist,
        key: find_key(&plain),
        capo: find_capo(&plain),
        bpm: crate::song::bpm_in(&plain),
        text,
    }
}

/// "Tom: G" (o acorde pode vir na linha de baixo, em outra tag).
fn find_key(plain: &str) -> String {
    let lower = plain.to_lowercase();
    let Some(i) = lower.find("tom:") else {
        return String::new();
    };
    let rest: String = plain[i + 4..].chars().take(60).collect();
    crate::song::key_from(&rest)
}

fn find_capo(plain: &str) -> u32 {
    let lower = plain.to_lowercase();
    let Some(i) = lower.find("capotraste") else {
        return 0;
    };
    lower[i..]
        .chars()
        .take(40)
        .skip_while(|c| !c.is_ascii_digit())
        .take_while(|c| c.is_ascii_digit())
        .collect::<String>()
        .parse()
        .unwrap_or(0)
}

pub fn extract_json(html: &str) -> String {
    serde_json::to_string(&extract(html)).unwrap_or_else(|_| "{}".into())
}

/// "Música - Artista - Cifra Club" ou "Artista - Música (Cifra)".
fn title_artist(html: &str) -> (String, String) {
    let meta = meta_content(html, "og:title");
    let t = meta.unwrap_or_else(|| {
        blocks(html, "title")
            .first()
            .map(|s| decode(s))
            .unwrap_or_default()
    });
    let parts: Vec<String> = t
        .split([' ', '\u{a0}'])
        .collect::<Vec<_>>()
        .join(" ")
        .split(" - ")
        .map(|p| clean_title(p.trim()))
        .filter(|p| !p.is_empty())
        .collect();
    match parts.len() {
        0 => (String::new(), String::new()),
        1 => (parts[0].clone(), String::new()),
        _ => (parts[0].clone(), parts[1].clone()),
    }
}

/// Tira "(Cifra)", "Cifra de", "Tab" e o nome do site do título.
fn clean_title(s: &str) -> String {
    let mut s = s.to_string();
    for junk in [
        "(Cifra)",
        "(cifra)",
        "(Tab)",
        "(tab)",
        "Cifra de ",
        "Cifra: ",
    ] {
        s = s.replace(junk, "");
    }
    let lower = s.to_lowercase();
    if lower.contains("cifra club") || lower.contains("cifras.com") || lower.ends_with(".com") {
        return String::new();
    }
    s.trim().to_string()
}

fn meta_content(html: &str, property: &str) -> Option<String> {
    let lower = html.to_lowercase();
    let key = format!("\"{property}\"");
    let at = lower.find(&key)?;
    let start = lower[..at].rfind('<')?;
    let end = at + lower[at..].find('>')?;
    let tag = &html[start..end];
    let c = tag.to_lowercase().find("content=")? + "content=".len();
    let rest = &tag[c..];
    let q = rest.chars().next()?;
    if q != '"' && q != '\'' {
        return None;
    }
    let close = rest[1..].find(q)?;
    Some(decode(&rest[1..1 + close]))
}

/// Conteúdo de cada `<tag ...>...</tag>` (sem aninhar).
fn blocks<'a>(html: &'a str, tag: &str) -> Vec<&'a str> {
    let lower = html.to_lowercase();
    let open = format!("<{tag}");
    let close = format!("</{tag}");
    let mut out = Vec::new();
    let mut pos = 0;
    while let Some(i) = lower[pos..].find(&open) {
        let i = pos + i;
        // "<pre" e não "<prefix": o próximo caractere fecha o nome.
        let after = lower[i + open.len()..].chars().next().unwrap_or('>');
        if !(after == '>' || after.is_whitespace() || after == '/') {
            pos = i + open.len();
            continue;
        }
        let Some(gt) = lower[i..].find('>') else {
            break;
        };
        let start = i + gt + 1;
        let Some(end) = lower[start..].find(&close) else {
            break;
        };
        out.push(&html[start..start + end]);
        pos = start + end + close.len();
    }
    out
}

fn strip_blocks(html: &str, tag: &str) -> String {
    let mut s = html.to_string();
    let open = format!("<{tag}");
    let close = format!("</{tag}>");
    loop {
        let lower = s.to_lowercase();
        let Some(i) = lower.find(&open) else { break };
        let Some(j) = lower[i..].find(&close) else {
            s.truncate(i);
            break;
        };
        s.replace_range(i..i + j + close.len(), "");
    }
    s
}

/// HTML -> texto. Em `<pre>` os espaços e quebras já são os da página;
/// fora dele, `<br>`, `</p>`, `</div>` e `</li>` viram quebra de linha.
fn to_text(html: &str, block_breaks: bool) -> String {
    let mut out = String::with_capacity(html.len());
    let mut chars = html.char_indices().peekable();
    while let Some((i, c)) = chars.next() {
        if c != '<' {
            if block_breaks && c == '\n' {
                out.push(' ');
            } else {
                out.push(c);
            }
            continue;
        }
        let Some(len) = html[i..].find('>') else {
            break;
        };
        let tag = html[i + 1..i + len].trim().to_lowercase();
        let name: String = tag
            .trim_start_matches('/')
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect();
        if name == "br"
            || (block_breaks
                && tag.starts_with('/')
                && matches!(
                    name.as_str(),
                    "p" | "div" | "li" | "h1" | "h2" | "h3" | "tr"
                ))
        {
            out.push('\n');
        }
        while let Some(&(k, _)) = chars.peek() {
            if k > i + len {
                break;
            }
            chars.next();
        }
    }
    decode(&out)
}

fn decode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        rest = &rest[i..];
        let Some(end) = rest.find(';').filter(|&e| e <= 10) else {
            out.push('&');
            rest = &rest[1..];
            continue;
        };
        let ent = &rest[1..end];
        let ch = match ent {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" => Some('\''),
            "nbsp" => Some(' '),
            _ => ent
                .strip_prefix("#x")
                .or_else(|| ent.strip_prefix("#X"))
                .and_then(|h| u32::from_str_radix(h, 16).ok())
                .or_else(|| ent.strip_prefix('#').and_then(|d| d.parse().ok()))
                .and_then(char::from_u32),
        };
        match ch {
            Some(c) => {
                out.push(c);
                rest = &rest[end + 1..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_cifra_page() {
        let html = r#"<html><head><title>Minha Música - Banda Tal - Cifra Club</title>
<script>var x = "<pre>nada</pre>";</script></head><body>
<div>tom: <a><span>G</span></a> (com forma de <b>F</b>)</div><div>[Refrão] 120 bpm</div><div>Capotraste na 2ª casa</div>
<pre class="x">[Intro] <b>G</b>  <b>D/F#</b>  <b>Em</b>

[Primeira Parte]
<b>G</b>           <b>D</b>
Uma linha de letra &amp; mais

<span class="tablatura"><span class="cnt">E|-----3-----|
B|---0---0---|</span></span>
</pre></body></html>"#;
        let p = extract(html);
        assert_eq!(p.title, "Minha Música");
        assert_eq!(p.artist, "Banda Tal");
        assert_eq!((p.key.as_str(), p.capo, p.bpm), ("F", 2, 120));
        assert!(p
            .text
            .starts_with("[Intro] G  D/F#  Em\n\n[Primeira Parte]\nG           D"));
        assert!(p.text.contains("letra & mais"));
        assert!(p.text.contains("E|-----3-----|\nB|---0---0---|"));
        let s = crate::sheet::parse(&p.text);
        assert_eq!(s[0].chords, ["G", "D/F#", "Em"]);
        assert_eq!(s[1].tab.lines().count(), 2);
    }

    #[test]
    fn falls_back_to_body_and_og_title() {
        let html = r#"<head><meta property="og:title" content="Canção (Cifra) - Fulano"></head>
<body><div>[Refrão]</div><div><span>C</span> <span>G</span></div><p>letra</p></body>"#;
        let p = extract(html);
        assert_eq!((p.title.as_str(), p.artist.as_str()), ("Canção", "Fulano"));
        assert_eq!(p.text, "[Refrão]\nC G\nletra");
        assert_eq!(decode("&#233;&#xE9;&bogus; &"), "éé&bogus; &");
    }
}
