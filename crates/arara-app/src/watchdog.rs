//! Freeze reporter. The UI calls `beat()` every second (and `step()` at the
//! main startup stages). If the UI thread stops answering for a while, a
//! report with what every thread is waiting on is written to
//! ~/.cache/arara-music/travamentos/ and to the terminal, so a hang on the
//! user's machine can be diagnosed from one file.

use std::io::Write;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

static START: Mutex<Option<Instant>> = Mutex::new(None);
static LAST_BEAT_MS: AtomicU64 = AtomicU64::new(0);
static STEP: Mutex<String> = Mutex::new(String::new());

const STALL: Duration = Duration::from_secs(12);

fn elapsed_ms() -> u64 {
    START.lock().map(|s| s.map(|t| t.elapsed().as_millis() as u64).unwrap_or(0)).unwrap_or(0)
}

/// The UI thread is alive.
pub fn beat() {
    LAST_BEAT_MS.store(elapsed_ms().max(1), Ordering::Relaxed);
}

/// What the UI thread is about to do (shown in a freeze report).
pub fn step(what: &str) {
    log::debug!("startup: {what}");
    if let Ok(mut s) = STEP.lock() {
        s.clear();
        s.push_str(what);
    }
    beat();
}

pub fn start() {
    if let Ok(mut s) = START.lock() {
        *s = Some(Instant::now());
    }
    #[cfg(target_os = "linux")]
    unsafe {
        // Let the helper we spawn (eu-stack/gdb) attach to us even with Yama on.
        libc::prctl(libc::PR_SET_PTRACER, libc::PR_SET_PTRACER_ANY, 0, 0, 0);
    }
    let _ = std::thread::Builder::new().name("arara-watchdog".into()).spawn(|| {
        let mut reported = false;
        loop {
            std::thread::sleep(Duration::from_secs(1));
            let now = elapsed_ms();
            let last = LAST_BEAT_MS.load(Ordering::Relaxed);
            let stalled = now.saturating_sub(last) > STALL.as_millis() as u64;
            if stalled && !reported {
                reported = true;
                report(now.saturating_sub(last));
            } else if !stalled {
                reported = false;
            }
        }
    });
}

fn report(stalled_ms: u64) {
    let step = STEP.lock().map(|s| s.clone()).unwrap_or_default();
    let mut out = format!(
        "Arara Music {} travou: a interface não responde há {} s.\nÚltima etapa: {}\n\n",
        env!("CARGO_PKG_VERSION"),
        stalled_ms / 1000,
        if step.is_empty() { "(nenhuma)" } else { &step }
    );
    #[cfg(target_os = "linux")]
    {
        out.push_str("Threads (nome, estado, esperando em):\n");
        if let Ok(rd) = std::fs::read_dir("/proc/self/task") {
            for e in rd.flatten() {
                let p = e.path();
                let rd = |f: &str| std::fs::read_to_string(p.join(f)).unwrap_or_default().trim().to_string();
                let stat = rd("stat");
                let state = stat.rsplit(')').next().and_then(|r| r.split_whitespace().next()).unwrap_or("?").to_string();
                out.push_str(&format!("  {:>7} {:<20} {} {}\n", e.file_name().to_string_lossy(), rd("comm"), state, rd("wchan")));
            }
        }
        let pid = std::process::id().to_string();
        for (tool, args) in [
            ("eu-stack", vec!["-p", pid.as_str()]),
            ("gdb", vec!["-batch", "-nx", "-ex", "thread apply all bt 25", "-p", pid.as_str()]),
        ] {
            let res = std::process::Command::new("timeout").arg("30").arg(tool).args(&args).output();
            if let Ok(o) = res {
                if o.status.success() || !o.stdout.is_empty() {
                    out.push_str(&format!("\n--- {tool} ---\n"));
                    out.push_str(&String::from_utf8_lossy(&o.stdout));
                    out.push_str(&String::from_utf8_lossy(&o.stderr));
                    break;
                }
            }
        }
    }
    eprintln!("{out}");
    let dir = std::env::var_os("XDG_CACHE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".cache")))
        .map(|d| d.join("arara-music").join("travamentos"));
    if let Some(dir) = dir {
        let _ = std::fs::create_dir_all(&dir);
        let ts = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let path = dir.join(format!("travamento-{ts}.txt"));
        if let Ok(mut f) = std::fs::File::create(&path) {
            let _ = f.write_all(out.as_bytes());
            eprintln!("Relatório salvo em {}", path.display());
        }
    }
}
