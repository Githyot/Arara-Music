//! Arara Music core: library index, scanner, cover cache and lyrics.
//! Toolkit-agnostic; the Qt/QML front-end lives in `arara-app`.

pub mod covers;
pub mod downloads;
pub mod explicit;
pub mod freemusic;
pub mod db;
pub mod import;
pub mod lyrics;
pub mod natural;
pub mod query;
pub mod remote;
pub mod scanner;
pub mod watcher;

use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("database: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("image: {0}")]
    Image(#[from] image::ImageError),
}

pub type Result<T> = std::result::Result<T, Error>;

/// Standard XDG locations (~/.local/share/arara-music, ~/.cache/arara-music).
pub struct Paths {
    pub db: PathBuf,
    pub covers: PathBuf,
}

impl Paths {
    pub fn xdg() -> Self {
        let d = directories::ProjectDirs::from("io.github", "Githyot", "AraraMusic")
            .expect("no home directory");
        Paths {
            db: d.data_dir().join("library.db"),
            covers: d.cache_dir().join("covers"),
        }
    }
}
