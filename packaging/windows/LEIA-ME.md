# Build para Windows (cruzado, a partir do Linux)

1. Qt oficial via aqtinstall: `aqt install-qt windows desktop 6.8.3 win64_mingw -m qtmultimedia qtshadertools qtimageformats -O /opt/Qt`
   e `aqt install-qt linux desktop 6.8.3 linux_gcc_64 -m qtshadertools -O /opt/Qt` (ferramentas moc/rcc do host).
2. `qmake` cruzado: script que chama o qmake do gcc_64 com `-qtconf target_qt.conf` (Prefix=mingw_64, HostPrefix=gcc_64, TargetSpec=win32-g++).
   O rcc do host precisa de `--no-zstd` (o Qt do Windows não tem zstd).
3. `rustup target add x86_64-pc-windows-gnu`; compilador `x86_64-w64-mingw32-g++-posix`;
   linker = `mingw-link.sh` (põe `-lgcc_s` antes de `-lgcc_eh`; sem isso o std::call_once trava na abertura).
4. `cargo build --release --target x86_64-pc-windows-gnu -p arara-app`
5. `windeployqt.exe --release --qmldir crates/arara-app/qml arara-music.exe` (roda no Wine) + libstdc++-6, libgcc_s_seh-1, libwinpthread-1 do MinGW.
6. `makensis arara.nsi` gera o instalador.
