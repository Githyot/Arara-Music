//! Watches the library folders and calls back once things settle down.
//!
//! Copying an album fires hundreds of events; we wait until the folder has been
//! quiet for `debounce` before asking for a rescan (which is incremental, so it
//! only reads the new/changed files).

use notify::{RecursiveMode, Watcher};
use std::path::PathBuf;
use std::time::Duration;

use crate::scanner::AUDIO_EXTENSIONS;

pub struct LibraryWatcher {
    _inner: notify::RecommendedWatcher,
}

fn relevant(ev: &notify::Event) -> bool {
    use notify::EventKind::*;
    matches!(ev.kind, Create(_) | Modify(_) | Remove(_))
        && ev.paths.iter().any(|p| {
            // directories (no extension) matter too: a whole album folder can be moved in
            p.extension().is_none()
                || p
                    .extension()
                    .and_then(|e| e.to_str())
                    .map(|e| {
                        let e = e.to_ascii_lowercase();
                        AUDIO_EXTENSIONS.contains(&e.as_str()) || matches!(e.as_str(), "jpg" | "jpeg" | "png" | "lrc")
                    })
                    .unwrap_or(false)
        })
}

impl LibraryWatcher {
    pub fn new(
        roots: &[PathBuf],
        debounce: Duration,
        on_change: impl Fn() + Send + 'static,
    ) -> notify::Result<Self> {
        let (tx, rx) = crossbeam_channel::unbounded::<()>();
        let mut w = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
            if let Ok(ev) = res {
                if relevant(&ev) {
                    let _ = tx.send(());
                }
            }
        })?;
        for r in roots {
            // One unreadable folder (e.g. a locked external disk) must not
            // turn off watching for the others.
            if let Err(e) = w.watch(r, RecursiveMode::Recursive) {
                log::warn!("not watching {}: {e}", r.display());
            }
        }
        std::thread::Builder::new()
            .name("arara-watch".into())
            .spawn(move || {
                while rx.recv().is_ok() {
                    // drain until quiet
                    while rx.recv_timeout(debounce).is_ok() {}
                    on_change();
                }
            })
            .ok();
        Ok(Self { _inner: w })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    #[test]
    fn debounces_bursts() {
        let dir = tempfile::tempdir().unwrap();
        let hits = Arc::new(AtomicUsize::new(0));
        let h = hits.clone();
        let _w = LibraryWatcher::new(&[dir.path().to_path_buf()], Duration::from_millis(300), move || {
            h.fetch_add(1, Ordering::SeqCst);
        })
        .unwrap();
        std::thread::sleep(Duration::from_millis(100));
        for i in 0..50 {
            std::fs::write(dir.path().join(format!("{i}.mp3")), b"x").unwrap();
        }
        std::fs::write(dir.path().join("notes.md"), b"ignored").unwrap();
        std::thread::sleep(Duration::from_millis(1200));
        assert_eq!(hits.load(Ordering::SeqCst), 1);
    }
}
