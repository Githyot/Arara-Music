//! Desktop integration over D-Bus:
//! * MPRIS 2 (`org.mpris.MediaPlayer2.arara`): media keys, GNOME's top-bar
//!   media controls, lock screen, headphone buttons.
//! * XDG Settings portal: system light/dark preference and accent color, live.

use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::Arc;

use zbus::blocking::{connection, Connection};
use zbus::object_server::SignalContext;
use zbus::zvariant::{ObjectPath, OwnedValue, Value};

const PATH: &str = "/org/mpris/MediaPlayer2";

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Command {
    Play,
    Pause,
    PlayPause,
    Stop,
    Next,
    Previous,
    /// relative offset, microseconds
    Seek(i64),
    /// absolute position, microseconds
    SetPosition(i64),
    Raise,
    Quit,
}

type Handler = Arc<dyn Fn(Command) + Send + Sync>;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct TrackMeta {
    pub id: i64,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub art_url: String,
    pub length_us: i64,
}

struct Root {
    handler: Handler,
}

#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {
        (self.handler)(Command::Raise)
    }
    fn quit(&self) {
        (self.handler)(Command::Quit)
    }
    #[zbus(property)]
    fn can_quit(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_raise(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn identity(&self) -> String {
        "Arara Music".into()
    }
    #[zbus(property)]
    fn desktop_entry(&self) -> String {
        "io.github.Githyot.AraraMusic".into()
    }
    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        vec!["file".into()]
    }
    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        ["audio/mpeg", "audio/flac", "audio/ogg", "audio/opus", "audio/mp4", "audio/x-wav"]
            .iter()
            .map(|s| s.to_string())
            .collect()
    }
}

struct Player {
    handler: Handler,
    status: String,
    meta: Option<TrackMeta>,
    position: Arc<AtomicI64>,
    volume: f64,
    can_next: bool,
    can_prev: bool,
}

fn ov<'a>(v: impl Into<Value<'a>>) -> OwnedValue {
    OwnedValue::try_from(v.into()).expect("plain value")
}

#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    fn play(&self) {
        (self.handler)(Command::Play)
    }
    fn pause(&self) {
        (self.handler)(Command::Pause)
    }
    fn play_pause(&self) {
        (self.handler)(Command::PlayPause)
    }
    fn stop(&self) {
        (self.handler)(Command::Stop)
    }
    fn next(&self) {
        (self.handler)(Command::Next)
    }
    fn previous(&self) {
        (self.handler)(Command::Previous)
    }
    fn seek(&self, offset: i64) {
        (self.handler)(Command::Seek(offset))
    }
    fn set_position(&self, track_id: ObjectPath<'_>, position: i64) {
        // Spec: ignore if the track id is stale.
        let current = self.meta.as_ref().map(|m| track_path(m.id));
        if current.as_deref() == Some(track_id.as_str()) {
            (self.handler)(Command::SetPosition(position))
        }
    }
    fn open_uri(&self, _uri: String) {}

    #[zbus(property)]
    fn playback_status(&self) -> String {
        self.status.clone()
    }
    #[zbus(property)]
    fn loop_status(&self) -> String {
        "None".into()
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn shuffle(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        let mut m = HashMap::new();
        let Some(t) = &self.meta else {
            m.insert("mpris:trackid".into(), ov(ObjectPath::from_static_str_unchecked("/org/mpris/MediaPlayer2/TrackList/NoTrack")));
            return m;
        };
        m.insert("mpris:trackid".into(), ov(ObjectPath::try_from(track_path(t.id)).unwrap()));
        m.insert("mpris:length".into(), ov(t.length_us));
        m.insert("xesam:title".into(), ov(t.title.as_str()));
        m.insert("xesam:artist".into(), ov(vec![t.artist.as_str()]));
        m.insert("xesam:album".into(), ov(t.album.as_str()));
        if !t.art_url.is_empty() {
            m.insert("mpris:artUrl".into(), ov(t.art_url.as_str()));
        }
        m
    }
    #[zbus(property)]
    fn volume(&self) -> f64 {
        self.volume
    }
    #[zbus(property)]
    fn set_volume(&mut self, v: f64) {
        self.volume = v.clamp(0.0, 1.0);
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        self.position.load(Ordering::Relaxed)
    }
    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        self.can_next
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        self.can_prev
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        self.meta.is_some()
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        self.meta.is_some()
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        self.meta.is_some()
    }
    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }

    #[zbus(signal)]
    async fn seeked(ctxt: &SignalContext<'_>, position: i64) -> zbus::Result<()>;
}

fn track_path(id: i64) -> String {
    format!("/io/github/arara/track/{id}")
}

pub struct Mpris {
    conn: Connection,
    position: Arc<AtomicI64>,
}

impl Mpris {
    pub fn start(handler: impl Fn(Command) + Send + Sync + 'static) -> zbus::Result<Self> {
        let handler: Handler = Arc::new(handler);
        let position = Arc::new(AtomicI64::new(0));
        let conn = connection::Builder::session()?
            .name(format!("org.mpris.MediaPlayer2.arara.instance{}", std::process::id()))?
            .serve_at(PATH, Root { handler: handler.clone() })?
            .serve_at(
                PATH,
                Player {
                    handler,
                    status: "Stopped".into(),
                    meta: None,
                    position: position.clone(),
                    volume: 1.0,
                    can_next: false,
                    can_prev: false,
                },
            )?
            .build()?;
        Ok(Self { conn, position })
    }

    /// Push the current state; emits PropertiesChanged only for what changed.
    pub fn update(&self, status: &str, meta: Option<TrackMeta>, can_next: bool, can_prev: bool, volume: f64) {
        let Ok(iface) = self.conn.object_server().interface::<_, Player>(PATH) else { return };
        let ctx = iface.signal_context();
        let mut p = iface.get_mut();
        if p.status != status {
            p.status = status.to_string();
            let _ = zbus::block_on(p.playback_status_changed(ctx));
        }
        if p.meta != meta {
            p.meta = meta;
            let _ = zbus::block_on(p.metadata_changed(ctx));
            let _ = zbus::block_on(p.can_play_changed(ctx));
            let _ = zbus::block_on(p.can_seek_changed(ctx));
        }
        if p.can_next != can_next {
            p.can_next = can_next;
            let _ = zbus::block_on(p.can_go_next_changed(ctx));
        }
        if p.can_prev != can_prev {
            p.can_prev = can_prev;
            let _ = zbus::block_on(p.can_go_previous_changed(ctx));
        }
        if (p.volume - volume).abs() > 0.001 {
            p.volume = volume;
            let _ = zbus::block_on(p.volume_changed(ctx));
        }
    }

    /// Position is polled by clients (not change-notified), so this is cheap to call often.
    pub fn set_position(&self, us: i64) {
        self.position.store(us, Ordering::Relaxed);
    }

    /// Call after a user-initiated jump so shells update their progress bar.
    pub fn seeked(&self, us: i64) {
        self.set_position(us);
        if let Ok(iface) = self.conn.object_server().interface::<_, Player>(PATH) {
            let _ = zbus::block_on(Player::seeked(iface.signal_context(), us));
        }
    }
}

// ---------------- appearance (XDG Settings portal) ----------------

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Appearance {
    pub dark: Option<bool>,
    /// sRGB 0..1
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

fn unwrap_variant(v: OwnedValue) -> Value<'static> {
    let mut v: Value<'static> = v.into();
    while let Value::Value(inner) = v {
        v = *inner;
    }
    v
}

fn apply(app: &mut Appearance, key: &str, v: OwnedValue) {
    let v = unwrap_variant(v);
    match key {
        "color-scheme" => {
            if let Ok(n) = u32::try_from(&v) {
                app.dark = Some(n == 1);
            }
        }
        "accent-color" => {
            if let Ok((r, g, b)) = <(f64, f64, f64)>::try_from(v) {
                // out-of-range means "no accent set"
                if (0.0..=1.0).contains(&r) && (0.0..=1.0).contains(&g) && (0.0..=1.0).contains(&b) {
                    app.accent = Some((r, g, b));
                }
            }
        }
        _ => {}
    }
}

fn portal(conn: &Connection) -> zbus::Result<zbus::blocking::Proxy<'static>> {
    zbus::blocking::Proxy::new(
        conn,
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Settings",
    )
}

pub fn read_appearance() -> Appearance {
    let mut app = Appearance::default();
    let Ok(conn) = Connection::session() else { return app };
    let Ok(p) = portal(&conn) else { return app };
    for key in ["color-scheme", "accent-color"] {
        let v: zbus::Result<OwnedValue> = p
            .call("ReadOne", &("org.freedesktop.appearance", key))
            .or_else(|_| p.call("Read", &("org.freedesktop.appearance", key)));
        if let Ok(v) = v {
            apply(&mut app, key, v);
        }
    }
    app
}

/// Calls `on_change` with the new appearance whenever the user flips dark
/// mode or picks another accent color in GNOME Settings.
pub fn watch_appearance(on_change: impl Fn(Appearance) + Send + 'static) {
    std::thread::Builder::new()
        .name("arara-portal".into())
        .spawn(move || {
            let Ok(conn) = Connection::session() else { return };
            let Ok(p) = portal(&conn) else { return };
            let Ok(signals) = p.receive_signal("SettingChanged") else { return };
            let mut app = read_appearance();
            for msg in signals {
                let Ok((ns, key, v)) = msg.body().deserialize::<(String, String, OwnedValue)>() else { continue };
                if ns == "org.freedesktop.appearance" {
                    let before = app;
                    apply(&mut app, &key, v);
                    if app != before {
                        on_change(app);
                    }
                }
            }
        })
        .ok();
}
