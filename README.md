# Arara Music

Player de música para Linux em **Rust + Qt/QML**, com visual inspirado no GNOME/Adwaita, pensado para abrir na hora e gastar pouca memória mesmo com bibliotecas grandes.

- Índice da biblioteca em SQLite: abre instantaneamente e reindexa só o que mudou
- Capas em cache no disco (uma por álbum), carregadas só quando aparecem na tela
- Letras sincronizadas com **modo karaokê** palavra por palavra (arquivos `.lrc`, tags embutidas e [LRCLIB](https://lrclib.net))
- Busca instantânea (FTS5, ignora acentos)
- Álbuns, artistas, favoritas, recentes e playlists
- Fila com "tocar a seguir", aleatório e repetir; a fila e a posição voltam quando você reabre o app
- Teclas de mídia e controles de mídia do GNOME (MPRIS)
- Novas músicas na pasta aparecem sozinhas (monitoramento com inotify)
- Tema claro/escuro e cor de destaque do GNOME, ao vivo (portal de configurações)
- Editor de letras: sincronize tocando a música e apertando Enter em cada verso, salve como `.lrc` e envie ao LRCLIB
- Servidores **Navidrome/Subsonic** e **Jellyfin** junto com as músicas locais; o catálogo fica em cache e abre na hora, até offline
- Importa playlists e curtidas do **Apple Music** (Library.xml) e do **YouTube Music** (Google Takeout), além de CSV/M3U/XSPF, casando com as músicas que você tem
- Normalização de volume (ReplayGain), volume lembrado, menu principal e janela adaptável a telas estreitas
- Arrastar para reordenar fila e playlists; ordenação natural ("Artista 2" antes de "Artista 10")
- Testado com 50 mil faixas: indexa em ~4 s e abre a janela em ~0,2 s

Veja a análise e as medições em [docs/ANALISE.md](docs/ANALISE.md).

## Estrutura

```
crates/arara-core   núcleo sem interface: banco, scanner, cache de capas, letras, servidores remotos
crates/arara-cli    `arara`: linha de comando para indexar, buscar e testar letras
crates/arara-app    `arara-music`: interface Qt/QML (cxx-qt)
```

## Compilar

Dependências (Ubuntu/Debian):

```sh
sudo apt install qt6-base-dev qt6-declarative-dev qt6-multimedia-dev \
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
  qml6-module-qtquick-window qml6-module-qtquick-templates qml6-module-qtmultimedia \
  qml6-module-qtqml-workerscript qml6-module-qtquick-dialogs \
  qml6-module-qt-labs-folderlistmodel libqt6svg6 gstreamer1.0-plugins-good
```

Fedora: `sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtmultimedia-devel`

```sh
export QMAKE=$(command -v qmake6 || echo /usr/lib/qt6/bin/qmake)
cargo build --release
./target/release/arara-music          # usa a pasta Músicas (xdg-user-dir MUSIC)
```

Variáveis úteis: `ARARA_LIBRARY=/caminho` (pasta da biblioteca), `ARARA_DARK=1`, `ARARA_OFFLINE=1` (não consulta o LRCLIB) e `--ssd` (usa a barra de título do sistema em vez da própria).

## RPM (Fedora 40 ou mais novo)

```sh
cargo build --release
mkdir -p ~/rpmbuild/SOURCES && strip -o ~/rpmbuild/SOURCES/arara-music target/release/arara-music \
  && strip -o ~/rpmbuild/SOURCES/arara target/release/arara \
  && cp data/*.desktop data/*.metainfo.xml data/icons/*.svg LICENSE ~/rpmbuild/SOURCES/
rpmbuild -bb packaging/arara-music.spec
sudo dnf install ~/rpmbuild/RPMS/x86_64/arara-music-*.rpm
```

## Flatpak

```sh
# gera as fontes offline do Cargo (uma vez, e sempre que o Cargo.lock mudar)
curl -LO https://raw.githubusercontent.com/flatpak/flatpak-builder-tools/master/cargo/flatpak-cargo-generator.py
python3 flatpak-cargo-generator.py Cargo.lock -o build-aux/cargo-sources.json
flatpak-builder --user --install --force-clean build build-aux/io.github.Githyot.AraraMusic.yml
flatpak run io.github.Githyot.AraraMusic
```

## Atalhos

Espaço tocar/pausar · Ctrl+→/← próxima/anterior · Ctrl+F buscar · Ctrl+L letra · Esc voltar · Ctrl+Q sair

## Linha de comando

```sh
arara scan ~/Música      # indexa (incremental)
arara albums             # lista do cache
arara search beatles yel # busca
arara lyrics 123         # resolve a letra da faixa 123
arara remote add subsonic https://musica.exemplo.com usuario senha
arara remote add jellyfin https://jellyfin.exemplo.com usuario senha
arara remote sync        # sincroniza os servidores
arara remote list
arara import ~/Downloads/Takeout   # ou Library.xml, .csv, .m3u
```

Para testar sem um servidor de verdade: `python3 tools/mock_server.py --audio musica.mp3 --covers pasta-com-jpgs/` sobe um Subsonic + Jellyfin falso (usuário e senha `demo`).

## Licença

GPL-3.0-or-later
