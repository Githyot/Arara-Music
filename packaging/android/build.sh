#!/bin/bash
# Gera o APK do Arara Music para Android (arm64-v8a).
# Precisa: Android SDK (platforms;android-34, build-tools;34.0.0,
# ndk;26.1.10909125), Qt 6.8.3 android_arm64_v8a + gcc_64 (aqtinstall),
# rustup target aarch64-linux-android. Saída: dist/arara-music-<versão>.apk
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
source packaging/android/env.sh
QT_HOST=$(dirname "$QT_ANDROID")/gcc_64
VERSION=$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)
export CARGO_TARGET_DIR=$ROOT/target-android
cargo build --release --target aarch64-linux-android -p arara-android

OUT=$ROOT/target-android/apk
rm -rf "$OUT" && mkdir -p "$OUT/libs/arm64-v8a"
cp "$CARGO_TARGET_DIR/aarch64-linux-android/release/libarara_music.so" "$OUT/libs/arm64-v8a/libarara-music_arm64-v8a.so"

IFS=. read -r MA MI PA <<< "$VERSION"
CODE=$((MA * 10000 + MI * 100 + PA))
cat > "$OUT/settings.json" <<JSON
{
  "description": "Arara Music",
  "qt": { "arm64-v8a": "$QT_ANDROID" },
  "qtDataDirectory": { "arm64-v8a": "." },
  "qtLibExecsDirectory": { "arm64-v8a": "libexec" },
  "qtLibsDirectory": { "arm64-v8a": "lib" },
  "qtPluginsDirectory": { "arm64-v8a": "plugins" },
  "qtQmlDirectory": { "arm64-v8a": "qml" },
  "qtHostDir": "$QT_HOST",
  "sdk": "$ANDROID_SDK_ROOT",
  "sdkBuildToolsRevision": "34.0.0",
  "ndk": "$ANDROID_NDK_ROOT",
  "toolchain-prefix": "llvm",
  "tool-prefix": "llvm",
  "ndk-host": "linux-x86_64",
  "architectures": { "arm64-v8a": "aarch64-linux-android" },
  "android-min-sdk-version": "28",
  "android-target-sdk-version": "34",
  "android-package-name": "io.github.githyot.araramusic",
  "android-app-name": "Arara Music",
  "android-version-code": "$CODE",
  "android-version-name": "$VERSION",
  "android-package-source-directory": "$ROOT/packaging/android/package",
  "qml-importscanner-binary": "$QT_HOST/libexec/qmlimportscanner",
  "rcc-binary": "$QT_HOST/libexec/rcc",
  "qml-root-path": ["$ROOT/crates/arara-app/qml"],
  "stdcpp-path": "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/",
  "application-binary": "arara-music",
  "zstdCompression": false
}
JSON
# O Maven Central às vezes responde 429 (muitos pedidos): o Gradle tenta de novo.
"$QT_HOST/bin/androiddeployqt" --input "$OUT/settings.json" --output "$OUT" \
  --android-platform android-34 --gradle --jdk "${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}" ||
  (cd "$OUT" && for i in 1 2 3; do ./gradlew --no-daemon --max-workers=2 assembleDebug && exit 0; sleep 20; done; exit 1)
mkdir -p dist
cp "$OUT/build/outputs/apk/debug/apk-debug.apk" "dist/arara-music-$VERSION.apk"
echo "APK: dist/arara-music-$VERSION.apk"
