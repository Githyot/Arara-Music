//! Windows stand-ins for the Linux desktop integration in `desktop.rs`
//! (MPRIS, XDG portals). Same API, so the bridge doesn't need to know.

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Command {
    Play,
    Pause,
    PlayPause,
    Stop,
    Next,
    Previous,
    Seek(i64),
    SetPosition(i64),
    Raise,
    Quit,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct TrackMeta {
    pub id: i64,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub art_url: String,
    pub length_us: i64,
}

/// Keeps Windows from sleeping while music plays (SetThreadExecutionState
/// is per-thread, so a small thread holds the request until dropped).
pub struct Inhibitor {
    stop: std::sync::mpsc::Sender<()>,
}

#[link(name = "kernel32")]
extern "system" {
    fn SetThreadExecutionState(flags: u32) -> u32;
}
const ES_CONTINUOUS: u32 = 0x8000_0000;
const ES_SYSTEM_REQUIRED: u32 = 0x0000_0001;

impl Inhibitor {
    pub fn start(_reason: &str) -> Option<Self> {
        let (tx, rx) = std::sync::mpsc::channel::<()>();
        std::thread::Builder::new()
            .name("arara-inhibit".into())
            .spawn(move || unsafe {
                SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED);
                let _ = rx.recv();
                SetThreadExecutionState(ES_CONTINUOUS);
            })
            .ok()?;
        Some(Inhibitor { stop: tx })
    }
}

impl Drop for Inhibitor {
    fn drop(&mut self) {
        let _ = self.stop.send(());
    }
}

pub struct Mpris;

impl Mpris {
    pub fn start(_handler: impl Fn(Command) + Send + Sync + 'static) -> Result<Self, String> {
        Err("MPRIS só existe no Linux".into())
    }
    pub fn update(&self, _status: &str, _meta: Option<TrackMeta>, _can_next: bool, _can_prev: bool, _volume: f64) {}
    pub fn lyric_line(&self, _line: &str, _next: &str, _title: &str, _artist: &str) {}
    pub fn set_position(&self, _us: i64) {}
    pub fn seeked(&self, _us: i64) {}
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Appearance {
    pub dark: Option<bool>,
    pub accent: Option<(f64, f64, f64)>,
}

impl Appearance {
    pub fn accent_hex(&self) -> Option<String> {
        self.accent.map(|(r, g, b)| {
            let c = |x: f64| (x.clamp(0.0, 1.0) * 255.0).round() as u8;
            format!("#{:02x}{:02x}{:02x}", c(r), c(g), c(b))
        })
    }
}

/// Windows "app mode" (light/dark) from the registry.
pub fn windows_prefers_dark() -> Option<bool> {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let out = std::process::Command::new("reg")
        .args(["query", r"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "/v", "AppsUseLightTheme"])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .ok()?;
    let s = String::from_utf8_lossy(&out.stdout);
    if s.contains("0x0") && !s.contains("0x1") {
        Some(true)
    } else if s.contains("0x1") {
        Some(false)
    } else {
        None
    }
}

pub fn read_appearance() -> Appearance {
    Appearance { dark: windows_prefers_dark(), accent: None }
}

pub fn watch_appearance(_on_change: impl Fn(Appearance) + Send + 'static) {}

/// No portal on Windows: the QML side falls back to Qt's own dialog.
pub fn portal_pick(_title: &str, _directory: bool, _filters: &[(&str, &[&str])]) -> Result<Option<String>, String> {
    Err("sem portal no Windows".into())
}
