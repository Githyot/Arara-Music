# Binary RPM built from the release binaries (cargo build --release).
# Needs glibc >= 2.39 and Qt >= 6.4: Fedora 40 or newer, openSUSE Tumbleweed.
%global debug_package %{nil}
%global __strip /bin/true
%{!?_metainfodir:%global _metainfodir %{_datadir}/metainfo}

Name:           arara-music
Version:        0.7.7
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
* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.7-1
- Retrospectiva (como Spotify Wrapped / Apple Music Replay): tempo ouvido por
  artista, música, álbum e gênero, por semana, mês, ano ou desde sempre
- Modo "story" em tela cheia com os destaques do período
- Registro só local; pode ser desligado ou apagado em Preferências > Biblioteca

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.6-1
- Transições entre músicas em Preferências > Reprodução: corte seco, sem
  intervalo (gapless), crossfade com curvas e mixagem inteligente
- Mixagem inteligente analisa o áudio (silêncio, fade-in/fade-out, loudness
  EBU R128 e andamento) e pode alinhar a transição na batida
- Crossfade curto ao pular música, fade ao pausar e retomar, álbuns sem
  crossfade, volume medido para músicas sem ReplayGain

* Fri Nov 06 2026 Arara Music <noreply@anthropic.com> - 0.7.5-1
- Menu da música mais completo: favoritar, compartilhar, criar estação, ir
  para o álbum/artista, informações e créditos, ver/copiar/editar letra,
  mostrar na pasta
- Página de informações da música com créditos (tags + MusicBrainz), samples,
  detalhes, estatísticas da biblioteca e dados do arquivo
- Barra "Sobre" para artistas e álbuns: foto e resumo da Wikipédia, dados do
  MusicBrainz, músicas mais tocadas, "Aparece em" e números da biblioteca
- Busca online pode ser desligada em Preferências > Biblioteca

* Fri Nov 06 2026 Arara Music <noreply@anthropic.com> - 0.7.4-1
- Velocidade de reprodução de 0,25x a 2x, em passos de 0,01 (botão entre os
  tempos do player, atalhos [ ] e \\, roda do mouse, MPRIS Rate)
- A letra karaokê acompanha a velocidade; o tom da voz é mantido no Qt 6.10+

* Fri Nov 06 2026 Arara Music <noreply@anthropic.com> - 0.7.3-1
- Selo E de explícito ao lado do nome das músicas (listas, painel, barra,
  tela de letra), lido das tags (iTunes/ID3/Vorbis), do Navidrome e do Jellyfin
- Detecção pela letra quando o arquivo não diz nada (pode ser desligada)
- Menu da música: "Marcar como explícita" / "Tirar o selo E"

* Fri Nov 06 2026 Arara Music <noreply@anthropic.com> - 0.7.2-1
- Botão Voltar em todas as telas internas (ano, gênero, compositor, pasta,
  artista, álbum), também com Alt+← e o botão "voltar" do mouse
- Páginas de categoria e de artista com título grande, Reproduzir e Aleatório
- Índice A–Z sempre visível, com a letra atual destacada
- Painel do player sem as abas grandes; botão Fila ao lado do botão de letra
- Painel: clicar no artista ou no álbum abre "Ver página do artista / do álbum"
- Álbum sem repetir o artista em cada faixa; telas vazias com ícone
* Fri Nov 06 2026 Arara Music <noreply@anthropic.com> - 0.7.1-1
- Letra: cada palavra sobe e cresce um pouco ao ser cantada, palavras longas
  crescem mais; relógio suave por quadro; bordas da letra dissolvem
- Correções: botão Voltar não aparecia, título da página sumia, espaço entre
  palavras da letra, barra de progresso vazia ao reabrir, cores dos
  interruptores, dicas nos botões de ícone, fechar letra com seta para baixo
* Fri Nov 06 2026 Arara Music <noreply@anthropic.com> - 0.7.0-1
- Temas GNOME, Apple, Android (Material 3) e Windows (Fluent), com
  claro/escuro, cor de destaque e troca ao vivo
- Seções da barra lateral recolhíveis; categorias agrupadas
- Janela de Preferências (Ctrl+,) com opções de aparência, reprodução,
  letras, biblioteca e janela

* Thu Nov 05 2026 Arara Music <noreply@anthropic.com> - 0.6.2-1
- Letra sincronizada no painel do player, abaixo dos controles; clique
  para ampliar. Favoritar e adicionar a playlist na tela de letra grande

* Thu Nov 05 2026 Arara Music <noreply@anthropic.com> - 0.6.1-1
- O som segue a saída escolhida no GNOME (fone, HDMI, line out), inclusive
  quando ela muda com a música tocando

* Thu Nov 05 2026 Arara Music <noreply@anthropic.com> - 0.6.0-1
- Música livre: busca no Jamendo e no Internet Archive (só Creative
  Commons e domínio público), toca na hora ou baixa para a biblioteca
  com tags, licença e letra sincronizada (.lrc) ao lado

* Thu Nov 05 2026 Arara Music <noreply@anthropic.com> - 0.5.1-1
- Corrige travamento durante a indexação (gravação em lotes curtos)
- Letra no estilo Apple Music: linha atual cresce, cascata suave, duetos
  dos dois lados, vocais de fundo menores; letra da versão certa (remix)
- Painel do player sempre à direita com fundo da capa e zoom ao pausar
- Capas com cantos arredondados, transições suaves, ícone com a arara

* Thu Nov 05 2026 Arara Music <noreply@anthropic.com> - 0.5.0-1
- Painel do player à direita (Player / Fila / Letra), tela de letra
  estilo karaokê, reprodução automática, volume largo
- Rolagem rápida com índice A–Z, gêneros, anos, compositores, pastas,
  coleções, busca com filtros e playlists inteligentes
- Várias pastas de música, selo Hi-Res/Sem perdas, letras baixadas em
  segundo plano, impede a suspensão enquanto toca, ícone novo

* Thu Nov 05 2026 Arara Music <noreply@anthropic.com> - 0.4.0-1
- Importação de playlists do Apple Music e YouTube Music, menu principal,
  ReplayGain, janela adaptável, servidores Navidrome/Jellyfin, editor de letras
