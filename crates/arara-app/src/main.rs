// No console window behind the app on Windows.
#![cfg_attr(windows, windows_subsystem = "windows")]

mod bridge;
mod cypher;
#[cfg(not(windows))]
mod desktop;
#[cfg(windows)]
#[path = "desktop_win.rs"]
mod desktop;
mod models;
mod watchdog;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

extern "C" {
    /// cpp/cypher/register.cpp: microfone do Arara Cypher para o QML.
    fn arara_cypher_register_types();
}

#[cfg(target_os = "android")]
extern "C" {
    /// cpp/android/permissions.cpp: pede acesso às músicas e ao microfone.
    fn arara_android_request_permissions();
}

/// Android: o Qt carrega libarara-music_arm64-v8a.so e chama `main` (ver
/// crates/arara-android). No desktop é o `main` normal do binário.
#[cfg(target_os = "android")]
#[export_name = "main"]
pub extern "C" fn android_main(_argc: i32, _argv: *const *const std::os::raw::c_char) -> i32 {
    main();
    0
}

fn main() {
    env_logger::init();
    watchdog::start();
    watchdog::step("iniciando o Qt");
    // Keep the scene graph lean: no MSAA, basic render loop on software GL.
    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Basic");
    }
    // The Wayland app_id (and the X11 hint GNOME uses) must match the
    // installed .desktop file, otherwise GNOME shows the running window with
    // a generic icon. Without this Qt builds the id from the organization
    // domain and the binary name ("githyot.github.io.arara-music").
    QGuiApplication::set_desktop_file_name(&QString::from("io.github.Githyot.AraraMusic"));
    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut().set_application_name(&QString::from("Arara Music"));
        app.as_mut().set_organization_domain(&QString::from("io.github.githyot"));
    }
    unsafe { arara_cypher_register_types() };
    #[cfg(target_os = "android")]
    unsafe {
        arara_android_request_permissions()
    };
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut engine) = engine.as_mut() {
        // Qt < 6.5 doesn't search qrc:/qt/qml by default.
        engine.as_mut().add_import_path(&QString::from("qrc:/qt/qml"));
        watchdog::step("carregando a interface (QML)");
        engine.as_mut().load(&QUrl::from("qrc:/qt/qml/io/github/arara/qml/ui/Main.qml"));
    }
    watchdog::step("interface carregada, mostrando a janela");
    let code = app.as_mut().map(|app| app.exec()).unwrap_or(0);
    // The window is closed and the queue/history were saved in onClosing.
    // Leave right away: tearing down media pipelines, D-Bus and worker threads
    // can hang, and a process left behind without a window looks like an app
    // that "won't open" the next time.
    watchdog::step("fechando");
    std::thread::spawn(|| {
        std::thread::sleep(std::time::Duration::from_secs(3));
        #[cfg(unix)]
        unsafe {
            libc::_exit(0)
        }
        #[cfg(not(unix))]
        std::process::abort();
    });
    std::process::exit(code);
}
