# Binary RPM built from the release binaries (cargo build --release).
# Needs glibc >= 2.39 and Qt >= 6.4: Fedora 40 or newer, openSUSE Tumbleweed.
%global debug_package %{nil}
%global __strip /bin/true

Name:           arara-music
Version:        0.4.0
Release:        1%{?dist}
Summary:        Player de música leve para GNOME, com letras sincronizadas
License:        GPL-3.0-or-later
URL:            https://github.com/Githyot/arara-music
ExclusiveArch:  x86_64

Requires:       qt6-qtbase
Requires:       qt6-qtbase-gui
Requires:       qt6-qtdeclarative
Requires:       qt6-qtmultimedia
Requires:       qt6-qtsvg
Recommends:     xdg-desktop-portal-gnome

%description
Arara Music é um player de música para Linux em Rust e Qt/QML, com visual
do GNOME. Abre na hora mesmo com bibliotecas grandes (índice em SQLite e
capas em cache no disco), mostra letras sincronizadas em modo karaokê
(LRCLIB), toca de servidores Navidrome/Subsonic e Jellyfin e importa
playlists e curtidas do Apple Music e do YouTube Music.

%install
install -Dm755 %{_sourcedir}/arara-music %{buildroot}%{_bindir}/arara-music
install -Dm755 %{_sourcedir}/arara %{buildroot}%{_bindir}/arara
install -Dm644 %{_sourcedir}/io.github.Githyot.AraraMusic.desktop %{buildroot}%{_datadir}/applications/io.github.Githyot.AraraMusic.desktop
install -Dm644 %{_sourcedir}/io.github.Githyot.AraraMusic.metainfo.xml %{buildroot}%{_metainfodir}/io.github.Githyot.AraraMusic.metainfo.xml
install -Dm644 %{_sourcedir}/io.github.Githyot.AraraMusic.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/io.github.Githyot.AraraMusic.svg
install -Dm644 %{_sourcedir}/LICENSE %{buildroot}%{_datadir}/licenses/%{name}/LICENSE

%files
%license %{_datadir}/licenses/%{name}/LICENSE
%{_bindir}/arara-music
%{_bindir}/arara
%{_datadir}/applications/io.github.Githyot.AraraMusic.desktop
%{_metainfodir}/io.github.Githyot.AraraMusic.metainfo.xml
%{_datadir}/icons/hicolor/scalable/apps/io.github.Githyot.AraraMusic.svg

%changelog
* Thu Nov 05 2026 Arara Music <noreply@anthropic.com> - 0.4.0-1
- Importação de playlists do Apple Music e YouTube Music, menu principal,
  ReplayGain, janela adaptável, servidores Navidrome/Jellyfin, editor de letras
