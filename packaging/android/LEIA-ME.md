# Build para Android (arm64)

O app Android é o mesmo código do `arara-app`, compilado como biblioteca
(`crates/arara-android`, com links para `../arara-app`) que o Qt carrega.

1. Qt oficial via aqtinstall (6.8.3): `linux desktop linux_gcc_64` (ferramentas do host)
   e `linux android android_arm64_v8a -m qtmultimedia qtshadertools qtimageformats`, em `/opt/Qt`.
2. Android SDK em `/opt/android/sdk` (commandlinetools de dl.google.com):
   `sdkmanager "platforms;android-34" "build-tools;34.0.0" "ndk;26.1.10909125"`.
3. `rustup target add aarch64-linux-android`.
4. `packaging/android/build.sh` → `dist/arara-music-<versão>.apk` (debug, assinado com a chave de debug).

Detalhes:
- `env.sh` aponta o cc/cargo para o clang do NDK e cria links `libQt6X.so` → `libQt6X_arm64-v8a.so`
  (o qt-build-utils pede os dois nomes).
- `package/` tem o AndroidManifest (permissões de áudio e microfone, ícone) e os ícones.
- Na abertura o app pede a permissão "Músicas e áudio" (`cpp/android/permissions.cpp`);
  a pasta padrão é `/storage/emulated/0/Music`.
