// Android: pede acesso às músicas (e ao microfone do afinador) na abertura.
// O Qt só tem classes públicas para microfone/câmera; para áudio usamos a
// API privada QtAndroidPrivate (cabeçalhos privados vêm de CXXFLAGS no
// packaging/android/env.sh).
#include <QtCore/private/qandroidextras_p.h>
#include <QtCore/QStringList>

extern "C" void arara_android_request_permissions()
{
    QtAndroidPrivate::requestPermissions(QStringList {
        QStringLiteral("android.permission.READ_MEDIA_AUDIO"),
        QStringLiteral("android.permission.READ_EXTERNAL_STORAGE"),
        QStringLiteral("android.permission.RECORD_AUDIO"),
    });
}
