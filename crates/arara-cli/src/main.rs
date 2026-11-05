//! `arara` — command-line companion used for benchmarks and debugging.
//!
//!   arara scan <dir>...          index (incremental)
//!   arara albums                 list albums from the cache
//!   arara search <words>         full-text search
//!   arara lyrics <track-id>      resolve lyrics (local + LRCLIB)
//!
//! Set ARARA_DB / ARARA_COVERS to override the XDG locations.

use arara_core::{covers::CoverCache, db::Db, lyrics, scanner, Paths};
use std::path::PathBuf;
use std::time::Instant;

fn main() {
    env_logger::init();
    let mut args = std::env::args().skip(1);
    let cmd = args.next().unwrap_or_default();
    let rest: Vec<String> = args.collect();

    let mut paths = Paths::xdg();
    if let Ok(p) = std::env::var("ARARA_DB") {
        paths.db = p.into();
    }
    if let Ok(p) = std::env::var("ARARA_COVERS") {
        paths.covers = p.into();
    }

    let t0 = Instant::now();
    let mut db = Db::open(&paths.db).expect("open db");
    let open_ms = t0.elapsed().as_secs_f64() * 1000.0;

    match cmd.as_str() {
        "scan" => {
            let covers = CoverCache::new(&paths.covers).unwrap();
            let roots: Vec<PathBuf> = rest.iter().map(PathBuf::from).collect();
            let s = scanner::scan(&mut db, &covers, &roots, |e| {
                if let scanner::ScanEvent::Parsed { done, total } = e {
                    eprintln!("  {done}/{total}");
                }
            })
            .unwrap();
            println!(
                "seen={} parsed={} unchanged={} removed={} failed={} covers={} in {} ms",
                s.seen, s.parsed, s.unchanged, s.removed, s.failed, s.covers_written, s.elapsed_ms
            );
        }
        "albums" => {
            let t = Instant::now();
            let a = db.albums().unwrap();
            let q = t.elapsed().as_secs_f64() * 1000.0;
            for al in a.iter().take(20) {
                println!("{:>5}  {} — {} ({} faixas)", al.id, al.artist.as_deref().unwrap_or("?"), al.title, al.track_count);
            }
            let (tr, al, ar) = db.counts().unwrap();
            println!("{tr} faixas, {al} álbuns, {ar} artistas | abrir db {open_ms:.1} ms, listar álbuns {q:.1} ms");
        }
        "search" => {
            for t in db.search(&rest.join(" "), 20).unwrap() {
                println!("{:>6}  {} — {}  [{}]", t.id, t.artist, t.title, t.album.unwrap_or_default());
            }
        }
        "lyrics" => {
            let id: i64 = rest.first().and_then(|s| s.parse().ok()).expect("track id");
            let client = lyrics::LrclibClient::default();
            match lyrics::resolve(&db, Some(&client), id).unwrap() {
                lyrics::Lyrics::Synced(lines) => {
                    for l in lines {
                        println!("[{:>6}] {}", l.start_ms, l.text);
                    }
                }
                lyrics::Lyrics::Plain(p) => println!("{p}"),
                lyrics::Lyrics::None => println!("(sem letra)"),
            }
        }
        _ => eprintln!("uso: arara scan <dir>... | albums | search <termos> | lyrics <id>"),
    }
}
