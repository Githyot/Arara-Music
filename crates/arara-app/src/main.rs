mod bridge;
mod desktop;
mod models;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    env_logger::init();
    // Keep the scene graph lean: no MSAA, basic render loop on software GL.
    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Basic");
    }
    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut().set_application_name(&QString::from("Arara Music"));
        app.as_mut().set_organization_domain(&QString::from("io.github.githyot"));
    }
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut engine) = engine.as_mut() {
        // Qt < 6.5 doesn't search qrc:/qt/qml by default.
        engine.as_mut().add_import_path(&QString::from("qrc:/qt/qml"));
        engine.as_mut().load(&QUrl::from("qrc:/qt/qml/io/github/arara/qml/ui/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
