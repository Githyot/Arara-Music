//! Biblioteca de cifras salva no aparelho: um arquivo JSON por música.
//!
//! O conteúdo de cada música é o mesmo formato das músicas de exemplo
//! (título, artista, tom, partes, batidas, formas). Este módulo só cuida de
//! guardar, listar e apagar; quem monta o JSON é a interface.

use serde_json::{Map, Value};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

/// Pasta padrão: `$XDG_DATA_HOME/araracypher/songs` ou
/// `~/.local/share/araracypher/songs`.
pub fn default_dir() -> PathBuf {
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("araracypher").join("songs")
}

/// Todas as músicas da pasta, ordenadas pelo título, como um array JSON.
/// Arquivos que não são JSON válido são ignorados.
pub fn list(dir: &Path) -> Vec<Value> {
    let mut songs: Vec<Value> = match fs::read_dir(dir) {
        Ok(entries) => entries
            .flatten()
            .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
            .filter_map(|e| fs::read_to_string(e.path()).ok())
            .filter_map(|text| serde_json::from_str::<Value>(&text).ok())
            .filter(|v| v.get("id").and_then(Value::as_str).is_some())
            .collect(),
        Err(_) => Vec::new(),
    };
    songs.sort_by_key(|v| {
        v.get("title")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_lowercase()
    });
    songs
}

pub fn list_json(dir: &Path) -> String {
    Value::Array(list(dir)).to_string()
}

/// Salva a música (JSON de um objeto). Sem `id`, cria um novo a partir do
/// título. Devolve o `id` usado.
pub fn save(dir: &Path, json: &str) -> io::Result<String> {
    let mut song: Map<String, Value> =
        serde_json::from_str(json).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let id = match song.get("id").and_then(Value::as_str) {
        Some(id) if valid_id(id) => id.to_string(),
        _ => new_id(song.get("title").and_then(Value::as_str).unwrap_or("")),
    };
    song.insert("id".into(), Value::String(id.clone()));
    fs::create_dir_all(dir)?;
    let text = serde_json::to_string_pretty(&Value::Object(song))
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    // A versão anterior vai para "historico/" (as 10 últimas de cada música),
    // para dar para voltar se algo der errado.
    let file = dir.join(format!("{id}.json"));
    if file.exists() {
        let _ = backup(dir, &id, &file);
    }
    // Grava num arquivo temporário e renomeia, para não perder a música se
    // o app fechar no meio.
    let tmp = dir.join(format!(".{id}.json.tmp"));
    fs::write(&tmp, text)?;
    fs::rename(&tmp, dir.join(format!("{id}.json")))?;
    Ok(id)
}

fn backup(dir: &Path, id: &str, file: &Path) -> io::Result<()> {
    let hist = dir.join("historico");
    fs::create_dir_all(&hist)?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    fs::copy(file, hist.join(format!("{id}.{stamp}.json")))?;
    let prefix = format!("{id}.");
    let mut old: Vec<PathBuf> = fs::read_dir(&hist)?
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.starts_with(&prefix) && n.ends_with(".json"))
        })
        .collect();
    old.sort();
    while old.len() > 10 {
        let _ = fs::remove_file(old.remove(0));
    }
    Ok(())
}

/// Apaga a música. Verdadeiro se o arquivo existia.
pub fn remove(dir: &Path, id: &str) -> bool {
    valid_id(id) && fs::remove_file(dir.join(format!("{id}.json"))).is_ok()
}

/// Só letras minúsculas, dígitos e hífen: nada de "../".
fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 80
        && id
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

/// "Asa Branca" -> "asa-branca-1731000000".
fn new_id(title: &str) -> String {
    let mut slug = String::new();
    for c in title.chars().flat_map(fold_accent) {
        if c.is_ascii_alphanumeric() {
            slug.push(c.to_ascii_lowercase());
        } else if !slug.ends_with('-') && !slug.is_empty() {
            slug.push('-');
        }
        if slug.len() >= 40 {
            break;
        }
    }
    let slug = slug.trim_end_matches('-');
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    if slug.is_empty() {
        format!("cifra-{stamp}")
    } else {
        format!("{slug}-{stamp}")
    }
}

pub(crate) fn fold_accent(c: char) -> Option<char> {
    Some(match c {
        'á' | 'à' | 'â' | 'ã' | 'ä' | 'Á' | 'À' | 'Â' | 'Ã' => 'a',
        'é' | 'ê' | 'è' | 'É' | 'Ê' => 'e',
        'í' | 'Í' => 'i',
        'ó' | 'ô' | 'õ' | 'Ó' | 'Ô' | 'Õ' => 'o',
        'ú' | 'ü' | 'Ú' => 'u',
        'ç' | 'Ç' => 'c',
        _ => c,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("araracypher-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn save_list_remove() {
        let dir = temp_dir("lib");
        let id = save(&dir, r#"{"title":"Asa Branca","key":"G","sections":[]}"#).unwrap();
        assert!(id.starts_with("asa-branca-"));
        let id2 = save(&dir, r#"{"title":"Ciúme de Você"}"#).unwrap();
        assert!(id2.starts_with("ciume-de-voce-"));

        let songs = list(&dir);
        assert_eq!(songs.len(), 2);
        assert_eq!(songs[0]["title"], "Asa Branca");

        // Salvar de novo com o mesmo id substitui.
        save(
            &dir,
            &format!(r#"{{"id":"{id}","title":"Asa Branca","key":"A"}}"#),
        )
        .unwrap();
        let songs = list(&dir);
        assert_eq!(songs.len(), 2);
        assert_eq!(songs[0]["key"], "A");
        // A versão anterior ficou guardada no histórico.
        let hist: Vec<_> = fs::read_dir(dir.join("historico"))
            .unwrap()
            .flatten()
            .collect();
        assert_eq!(hist.len(), 1);

        assert!(remove(&dir, &id));
        assert!(!remove(&dir, "../etc"));
        assert_eq!(list(&dir).len(), 1);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn bad_ids_get_replaced() {
        let dir = temp_dir("ids");
        let id = save(&dir, r#"{"id":"../../x","title":""}"#).unwrap();
        assert!(id.starts_with("cifra-"));
        assert!(save(&dir, "não é json").is_err());
        let _ = fs::remove_dir_all(&dir);
    }
}
