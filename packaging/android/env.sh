# Variáveis para compilar o Arara Music para Android (arm64).
# Uso: source packaging/android/env.sh
export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-/opt/android/sdk}
export ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT:-$ANDROID_SDK_ROOT/ndk/26.1.10909125}
export QT_ANDROID=${QT_ANDROID:-/opt/Qt/6.8.3/android_arm64_v8a}
API=28
TC=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin
export QMAKE=$QT_ANDROID/bin/qmake
export CC_aarch64_linux_android=$TC/aarch64-linux-android$API-clang
export CXX_aarch64_linux_android=$TC/aarch64-linux-android$API-clang++
export AR_aarch64_linux_android=$TC/llvm-ar
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$TC/aarch64-linux-android$API-clang++
export LANG=C.UTF-8
# Cabeçalhos privados do QtCore (QtAndroidPrivate::requestPermissions).
export CXXFLAGS_aarch64_linux_android="-I$QT_ANDROID/include/QtCore/6.8.3 -I$QT_ANDROID/include/QtCore/6.8.3/QtCore"
# O qt-build-utils também pede -lQt6Core (sem o sufixo _arm64-v8a): links
# com o nome curto, para o linker achar (o .so final continua pedindo o
# nome com sufixo, que é o soname).
QT_SHORT_LIBS=${QT_SHORT_LIBS:-$HOME/.cache/arara-android-qtlibs}
mkdir -p "$QT_SHORT_LIBS"
for f in "$QT_ANDROID"/lib/libQt6*_arm64-v8a.so; do
  b=$(basename "$f"); ln -sf "$f" "$QT_SHORT_LIBS/${b%_arm64-v8a.so}.so"
done
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-L $QT_SHORT_LIBS"
