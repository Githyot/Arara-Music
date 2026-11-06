//! Download queue for music the user may legally keep: free-licensed tracks
//! (Jamendo, Internet Archive) and, later, the user's own server files.
//!
//! - N worker threads read tasks from a channel; the UI is told about progress
//!   through a callback (the Qt side forwards it with `qt_thread().queue`).
//! - A task whose destination already exists (non-empty) finishes at once.
//! - Audio is written to `<dest>.part` and renamed only when complete, so the
//!   library watcher never indexes half a file.
//! - After the audio, synced lyrics are looked up on LRCLIB and saved as
//!   `<dest>.lrc` next to it (never overwriting one that is already there).

use std::collections::HashSet;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crossbeam_channel::{unbounded, Sender};

use crate::lyrics::LrclibClient;

#[derive(Debug, Clone)]
pub struct DownloadTask {
    pub id: String,
    pub url: String,
    pub dest: PathBuf,
    pub artist: String,
    pub title: String,
    pub album: String,
    pub duration_s: u64,
    /// Look up synced lyrics on LRCLIB after the audio is saved.
    pub lyrics: bool,
    /// Written to the file's comment tag (licence and where it came from).
    pub comment: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum DownloadEvent {
    Started { id: String },
    /// `total` is 0 when the server didn't say how big the file is.
    Progress { id: String, done: u64, total: u64 },
    /// The file was already in the library: nothing downloaded.
    AlreadyHere { id: String, path: PathBuf },
    Finished { id: String, path: PathBuf, lyrics: bool },
    Failed { id: String, error: String },
    Cancelled { id: String },
}

type Callback = Arc<dyn Fn(DownloadEvent) + Send + Sync>;

pub struct DownloadManager {
    tx: Sender<DownloadTask>,
    cancelled: Arc<Mutex<HashSet<String>>>,
    queued: Arc<Mutex<HashSet<String>>>,
}

impl DownloadManager {
    pub fn new(workers: usize, on_event: impl Fn(DownloadEvent) + Send + Sync + 'static) -> Self {
        let (tx, rx) = unbounded::<DownloadTask>();
        let cb: Callback = Arc::new(on_event);
        let cancelled = Arc::new(Mutex::new(HashSet::new()));
        let queued = Arc::new(Mutex::new(HashSet::new()));
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(10))
            .timeout_read(Duration::from_secs(30))
            .user_agent(concat!("Arara Music/", env!("CARGO_PKG_VERSION")))
            .build();
        for _ in 0..workers.max(1) {
            let (rx, cb, cancelled, queued, agent) = (rx.clone(), cb.clone(), cancelled.clone(), queued.clone(), agent.clone());
            std::thread::spawn(move || {
                let lrclib = LrclibClient::default();
                for task in rx {
                    let id = task.id.clone();
                    let ev = if cancelled.lock().unwrap().remove(&id) {
                        DownloadEvent::Cancelled { id: id.clone() }
                    } else {
                        run(&agent, &lrclib, &task, &*cb, &cancelled)
                    };
                    queued.lock().unwrap().remove(&id);
                    cb(ev);
                }
            });
        }
        Self { tx, cancelled, queued }
    }

    /// Queue a download. Returns false if the same id is already queued.
    pub fn enqueue(&self, task: DownloadTask) -> bool {
        if !self.queued.lock().unwrap().insert(task.id.clone()) {
            return false;
        }
        self.cancelled.lock().unwrap().remove(&task.id);
        self.tx.send(task).is_ok()
    }

    /// Stop a queued or running download; its `.part` file is removed.
    pub fn cancel(&self, id: &str) {
        if self.queued.lock().unwrap().contains(id) {
            self.cancelled.lock().unwrap().insert(id.to_string());
        }
    }
}

fn run(agent: &ureq::Agent, lrclib: &LrclibClient, t: &DownloadTask, cb: &dyn Fn(DownloadEvent), cancelled: &Mutex<HashSet<String>>) -> DownloadEvent {
    let id = t.id.clone();
    if exists_nonempty(&t.dest) {
        if t.lyrics {
            save_lyrics(lrclib, t);
        }
        return DownloadEvent::AlreadyHere { id, path: t.dest.clone() };
    }
    cb(DownloadEvent::Started { id: id.clone() });
    match fetch(agent, t, cb, cancelled) {
        Ok(true) => {
            if let Err(e) = write_tags(t) {
                log::info!("could not tag {}: {e}", t.dest.display());
            }
            let lyrics = t.lyrics && save_lyrics(lrclib, t);
            DownloadEvent::Finished { id, path: t.dest.clone(), lyrics }
        }
        Ok(false) => DownloadEvent::Cancelled { id },
        Err(e) => DownloadEvent::Failed { id, error: e },
    }
}

fn exists_nonempty(p: &Path) -> bool {
    std::fs::metadata(p).map(|m| m.is_file() && m.len() > 0).unwrap_or(false)
}

pub fn part_path(dest: &Path) -> PathBuf {
    let mut s = dest.as_os_str().to_owned();
    s.push(".part");
    PathBuf::from(s)
}

/// Ok(true) = saved, Ok(false) = cancelled.
fn fetch(agent: &ureq::Agent, t: &DownloadTask, cb: &dyn Fn(DownloadEvent), cancelled: &Mutex<HashSet<String>>) -> Result<bool, String> {
    if let Some(dir) = t.dest.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("não foi possível criar a pasta: {e}"))?;
    }
    let resp = agent.get(&t.url).call().map_err(|e| match e {
        ureq::Error::Status(code, _) => format!("o servidor respondeu {code}"),
        e => format!("sem conexão: {e}"),
    })?;
    let total: u64 = resp.header("Content-Length").and_then(|v| v.parse().ok()).unwrap_or(0);
    let part = part_path(&t.dest);
    let mut out = std::fs::File::create(&part).map_err(|e| format!("não foi possível gravar: {e}"))?;
    let mut body = resp.into_reader();
    let mut buf = vec![0u8; 64 * 1024];
    let (mut done, mut last) = (0u64, Instant::now());
    let result = loop {
        if cancelled.lock().unwrap().remove(&t.id) {
            break Ok(false);
        }
        match body.read(&mut buf) {
            Ok(0) => break Ok(true),
            Ok(n) => {
                if let Err(e) = out.write_all(&buf[..n]) {
                    break Err(format!("não foi possível gravar: {e}"));
                }
                done += n as u64;
                if last.elapsed() > Duration::from_millis(200) {
                    last = Instant::now();
                    cb(DownloadEvent::Progress { id: t.id.clone(), done, total });
                }
            }
            Err(e) => break Err(format!("a conexão caiu: {e}")),
        }
    };
    let result = result.and_then(|ok| {
        if ok && total > 0 && done < total {
            return Err(format!("download incompleto ({done} de {total} bytes)"));
        }
        if ok && done == 0 {
            return Err("o servidor mandou um arquivo vazio".into());
        }
        Ok(ok)
    });
    drop(out);
    match result {
        Ok(true) => {
            std::fs::rename(&part, &t.dest).map_err(|e| format!("não foi possível gravar: {e}"))?;
            Ok(true)
        }
        other => {
            let _ = std::fs::remove_file(&part);
            other
        }
    }
}

/// Title, artist and album from the source (files on the Internet Archive often
/// have no tags), plus the licence as a comment.
fn write_tags(t: &DownloadTask) -> Result<(), String> {
    use lofty::config::WriteOptions;
    use lofty::file::TaggedFileExt;
    use lofty::tag::{Accessor, ItemKey, Tag, TagExt};
    let mut f = lofty::read_from_path(&t.dest).map_err(|e| e.to_string())?;
    if f.primary_tag().is_none() {
        let tt = f.primary_tag_type();
        f.insert_tag(Tag::new(tt));
    }
    let tag = f.primary_tag_mut().ok_or("no tag")?;
    if !t.title.is_empty() {
        tag.set_title(t.title.clone());
    }
    if !t.artist.is_empty() {
        tag.set_artist(t.artist.clone());
    }
    if !t.album.is_empty() {
        tag.set_album(t.album.clone());
    }
    if !t.comment.is_empty() {
        tag.insert_text(ItemKey::Comment, t.comment.clone());
    }
    tag.save_to_path(&t.dest, WriteOptions::default()).map_err(|e| e.to_string())
}

/// Synced (or plain) lyrics from LRCLIB into `<dest>.lrc`. True if a file is there afterwards.
fn save_lyrics(lrclib: &LrclibClient, t: &DownloadTask) -> bool {
    let lrc = t.dest.with_extension("lrc");
    if lrc.exists() {
        return true;
    }
    let Ok(Some(rec)) = lrclib.find(&t.title, &t.artist, &t.album, t.duration_s) else { return false };
    let Some(text) = rec.synced_lyrics.or(rec.plain_lyrics).filter(|s| !s.trim().is_empty()) else { return false };
    let tmp = lrc.with_extension("lrc.part");
    let ok = std::fs::write(&tmp, text.replace("\r\n", "\n")).is_ok() && std::fs::rename(&tmp, &lrc).is_ok();
    if !ok {
        let _ = std::fs::remove_file(&tmp);
    }
    ok
}

/// `Artista/Álbum/Título.ext`, with characters that break file names replaced.
pub fn library_path(root: &Path, artist: &str, album: &str, title: &str, ext: &str) -> PathBuf {
    fn clean(s: &str, fallback: &str) -> String {
        let s: String = s
            .chars()
            .map(|c| if matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|') || c.is_control() { '_' } else { c })
            .collect();
        let s = s.trim().trim_matches('.').trim();
        let s: String = s.chars().take(120).collect();
        if s.is_empty() { fallback.to_string() } else { s }
    }
    let ext = ext.trim_start_matches('.');
    root.join(clean(artist, "Artista desconhecido"))
        .join(clean(album, "Singles"))
        .join(format!("{}.{}", clean(title, "Sem título"), if ext.is_empty() { "mp3" } else { ext }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader};
    use std::net::TcpListener;

    /// Tiny HTTP server: answers every request with `body`.
    fn serve(body: Vec<u8>, times: usize) -> String {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = l.local_addr().unwrap();
        std::thread::spawn(move || {
            for s in l.incoming().take(times) {
                let mut s = s.unwrap();
                let mut r = BufReader::new(s.try_clone().unwrap());
                let mut line = String::new();
                while r.read_line(&mut line).unwrap_or(0) > 2 {
                    line.clear();
                }
                let _ = write!(s, "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len());
                let _ = s.write_all(&body);
            }
        });
        format!("http://{addr}/song.mp3")
    }

    fn task(url: String, dest: PathBuf) -> DownloadTask {
        DownloadTask { id: "t1".into(), url, dest, artist: "A".into(), title: "B".into(), album: "".into(), duration_s: 0, lyrics: false, comment: String::new() }
    }

    #[test]
    fn downloads_then_skips_existing() {
        let dir = tempfile::tempdir().unwrap();
        let dest = library_path(dir.path(), "Ar/tista", "", "Faixa: 1", "mp3");
        assert!(dest.ends_with("Ar_tista/Singles/Faixa_ 1.mp3"));
        let url = serve(vec![7u8; 300_000], 1);
        let (tx, rx) = std::sync::mpsc::channel();
        let m = DownloadManager::new(2, move |e| { let _ = tx.send(e); });

        assert!(m.enqueue(task(url.clone(), dest.clone())));
        let done = rx.iter().find(|e| !matches!(e, DownloadEvent::Started { .. } | DownloadEvent::Progress { .. })).unwrap();
        assert_eq!(done, DownloadEvent::Finished { id: "t1".into(), path: dest.clone(), lyrics: false });
        assert_eq!(std::fs::metadata(&dest).unwrap().len(), 300_000);
        assert!(!part_path(&dest).exists());

        // Same file again: no request (the server would not answer), reported as already here.
        assert!(m.enqueue(task(url, dest.clone())));
        let again = rx.iter().find(|e| !matches!(e, DownloadEvent::Progress { .. })).unwrap();
        assert_eq!(again, DownloadEvent::AlreadyHere { id: "t1".into(), path: dest });
    }

    #[test]
    fn failure_leaves_no_partial_file() {
        let dir = tempfile::tempdir().unwrap();
        let dest = dir.path().join("x.mp3");
        let (tx, rx) = std::sync::mpsc::channel();
        let m = DownloadManager::new(1, move |e| { let _ = tx.send(e); });
        m.enqueue(task("http://127.0.0.1:9/nada.mp3".into(), dest.clone()));
        let ev = rx.iter().find(|e| matches!(e, DownloadEvent::Failed { .. })).unwrap();
        assert!(matches!(ev, DownloadEvent::Failed { .. }));
        assert!(!dest.exists() && !part_path(&dest).exists());
    }
}
