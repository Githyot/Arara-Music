# Binary RPM built from the release binaries (cargo build --release).
# Needs glibc >= 2.39 and Qt >= 6.4: Fedora 40 or newer, openSUSE Tumbleweed.
%global debug_package %{nil}
%global __strip /bin/true
%{!?_metainfodir:%global _metainfodir %{_datadir}/metainfo}

Name:           arara-music
Version:        0.7.44
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
# H.264 decoder for the animated album covers (falls back to the still cover without it)
Recommends:     openh264
Recommends:     xdg-desktop-portal-gnome
# Aba Estudos (Arara Cypher): ler cifra de um print
Recommends:     tesseract
Recommends:     tesseract-langpack-por

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
* Mon Nov 09 2026 Arara Music <noreply@anthropic.com> - 0.7.44-1
- Versão única com a 0.7.36 (trecho em loop), a 0.7.37–0.7.41 (aba Estudos
  com o Arara Cypher) e a 0.7.42 (mover a letra inteira no editor).

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.41-1
- Cifra: sem a seção "Batida" geral no topo (cada parte já mostra a batida
  na tab) e sem o botão "Partitura" (o "Tudo" já mostra a partitura).

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.40-1
- Editor de cifra: "Duplicar parte" copia a parte inteira (acordes, batida,
  tab e repetições) logo depois dela.

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.39-1
- Tabs: slide X/Y (sobe, ex.: 8/10) e X\Y (desce), com linha diagonal ligando
  as notas na tab e na partitura; no editor de tab, teclas / e \, botão
  "Slide" e campo "Slide até a casa".
- Estudos: dá para excluir as cifras de exemplo (continuam excluídas ao
  reabrir; "Restaurar exemplos" em Ajustes) e apagar as suas pela lista.
- Cifra aberta pela aba Estudos com a música na biblioteca: botão
  "Estudar com a música" (abre o modo Estudar com a faixa).
- "Editar cifra" no modo Estudar abre a cifra no editor (abria vazio).

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.38-1
- Estudos: cabeçalho da cifra sem sobreposição (título corta com "…") e
  botões com fundo; botão para esconder o player na aba Estudos.
- Batida: palhetada forte (acento) com seta grossa ⬇ ⬆ e ">" em cima da tab.

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.37-1
- Aba Estudos com o Arara Cypher inteiro: cifras, editor, afinador e estudo.
- "Estudar" nas músicas que têm cifra (menu ⋮, painel e tela da letra):
  cifra junto com a letra sincronizada, partes que acendem com a música,
  loop A–B, som da música liga/desliga, velocidade, treino de ouvido e
  contagem de 0 a 5 s antes do play.
* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.36-1
- Trecho em loop: no menu de três pontinhos, "Repetir um trecho em loop"
  pede o início e o fim (na letra ou pela posição atual) e repete essa
  parte até você desligar, para estudar. A tela da letra ganhou o menu
  de três pontinhos também.
* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.42-1
- Editor de letra (Sincronizar): "Mover a letra inteira" adianta ou atrasa
  todas as linhas de uma vez (passo ajustável, teclas − e +, Desfazer).

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.35-1
- Versão única com a 0.7.32 (números reais das faixas) e a 0.7.34
  (músicas repetidas mostram só a melhor cópia).

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.34-1
- Músicas repetidas (mesmo artista, álbum e título) aparecem uma vez só,
  na cópia de melhor qualidade; lista das cópias em Preferências >
  Biblioteca, com opção de escolher outra cópia. Nenhum arquivo é apagado.

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.32-1
- Página do álbum mostra o número real de cada faixa (da tag, ou do nome do
  arquivo quando não há tag), ordena por disco e faixa e avisa quais
  músicas do álbum não estão na biblioteca.

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.31-1
- Junta na main tudo até a 0.7.30 (PRs #13 e #14).
- Ícone da arara no dock e no Alt+Tab do GNOME com o app aberto: a janela
  agora se identifica como io.github.Githyot.AraraMusic, o mesmo nome do
  atalho instalado (antes aparecia a engrenagem genérica).

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.30-1
- Versão única com a 0.7.28 (trecho preferido) e a 0.7.29 (letras da
  palavra crescendo aos poucos no karaokê).

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.29-1
- Karaokê: as letras da palavra sobem e crescem uma a uma junto com o
  preenchimento, e a palavra só fica toda erguida quando termina de ser
  cantada (antes ela subia inteira logo no começo).

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.28-1
- Trecho preferido: na tela da letra, marque onde o trecho começa e
  termina (tocando nas linhas da letra ou na posição atual). Um botão ao
  lado da estrela toca só esse trecho, na tela da letra e no painel.

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.27-1
- Versão única com a 0.7.23 (mixagem inteligente), a 0.7.24 (letras ao
  lado das músicas), a 0.7.25 (informações de artistas e álbuns salvas
  junto com as músicas) e a 0.7.26 (lista de álbuns com capa animada).
- Capas animadas também na tela da letra, e no painel mesmo com a página
  do mesmo álbum aberta: um único vídeo é decodificado e mostrado nos
  dois lugares, então custa o mesmo que uma capa só.
- O loop não pisca mais: a capa parada não volta a aparecer quando o
  vídeo recomeça, nem quando a janela perde o foco.
- Barras de rolagem finas por cima do conteúdo, no estilo de cada tema:
  aparecem ao rolar ou ao passar o mouse e engrossam para arrastar. Nas
  letras, só aparecem quando você mesmo rola.

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.25-1
- Informações de todos os artistas e álbuns buscadas em segundo plano
  depois de indexar (MusicBrainz e Wikipédia, uma consulta por segundo),
  das mais tocadas para as menos tocadas, com contador na barra lateral.
  Continua de onde parou ao reabrir o app; para sozinha sem internet.
- As informações ficam salvas junto com as músicas, em arquivos ocultos:
  .arara-album.json na pasta do álbum e .arara-artist.json (com a foto
  .arara-artist.jpg) na pasta do artista. Se o banco do app se perder, ou
  em outro computador com o mesmo disco, tudo volta dos arquivos sem
  internet. Discos somente leitura ou bloqueados ficam só no cache do app.
- Álbum certo no MusicBrainz: usa a edição original (a primeira lançada)
  em vez de qualquer edição, como uma prensagem japonesa com faixa bônus.
  Código de barras só aparece quando as tags dizem qual edição é a sua.
- Preferências > Biblioteca: "Buscar de toda a biblioteca" e "Salvar junto
  com as músicas".
* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.26-1
- Capas animadas: Preferências > Biblioteca mostra a lista dos álbuns que
  ganharam capa animada ("Ver álbuns"); clicar num deles abre o álbum. A
  lista cresce enquanto "Baixar agora" encontra novas capas.
* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.23-1
- Mixagem inteligente conferida com áudio gravado. Correções:
- Curva DJ refeita: troca rápida no meio com potência constante (a antiga
  deixava um buraco de ~9 dB no volume no meio da transição)
- Alinhar na batida: a próxima música entrava ~0,16 s atrasada (tempo que o
  sistema leva para soltar o som); agora entra no tempo, com ajuste em
  Preferências > Reprodução > "Atraso para começar a próxima"
- Andamento medido com precisão de 0,1 BPM (121 era lido como 120, e as
  batidas se desencontravam durante a mistura); análises antigas são refeitas
- Sem intervalo (gapless) começa a próxima no momento certo, sem buraco
* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.24-1
- Letras ao lado das músicas: cada letra baixada do LRCLIB também é salva
  como .lrc (ou .txt) na pasta da música, com o mesmo nome. Arquivos que já
  existem nunca são trocados. As letras que já estavam no app são copiadas
  uma vez ao abrir. Opção e botão "Copiar agora" em Preferências > Letras.
- Pastas somente leitura e discos desconectados não travam nada: a letra
  continua guardada no app.

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.22-1
- Junta as capas animadas à versão 0.7.21.
- Capas animadas: quando o álbum tem capa animada no Apple Music, ela toca
  sem som na página do álbum e no painel. Opção em Preferências > Biblioteca
  (desligada por padrão), com "Baixar agora" para todos os álbuns e "Apagar".
  Cada capa é baixada uma vez (cerca de 2 MB) e fica no cache. O vídeo só
  roda com a janela em foco e na tela; fora disso fica a capa normal.

* Sun Nov 08 2026 Arara Music <noreply@anthropic.com> - 0.7.21-1
- Versão única que junta tudo desde a 0.7.12: editar informações da música
  (0.7.13), sem Música livre (0.7.14), sombra da capa (0.7.15), links e
  botão anterior na tela da letra (0.7.17), Reproduzir/Aleatório na busca e
  em todas as músicas (0.7.19) e a página Início (0.7.20)

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.20-1
- Nova página Início, primeira da barra lateral e aberta ao iniciar: botão
  grande "Tocar tudo aleatório" (e "Favoritas aleatórias"), álbuns ouvidos
  recentemente, mais tocadas, adicionados recentemente, seus artistas,
  tocadas recentemente e álbuns para redescobrir. Carrega depois que a
  janela aparece, com uma só consulta ao banco.

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.19-1
- Resultados da busca e "Todas as músicas" ganharam os botões "Reproduzir" e
  "Aleatório", como as páginas de álbum e de categoria
- "Aleatório" sorteia entre todas as músicas da lista, não só as 500
  primeiras

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.17-1
- Tela da letra: artista e álbum viraram links (abrem a página do artista e
  do álbum), como no painel lateral.
- Botão anterior: o segundo toque logo depois de voltar ao início vai para a
  música anterior, mesmo se o reprodutor ainda informa a posição antiga; os
  3 segundos contam a partir do início real da faixa (intro cortada); e ao
  tocar uma música de outra lista, o anterior volta para o que tocava antes.

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.15-1
- Sombra da capa no painel do player igual à do visual Apple: macia,
  desfocada e um pouco abaixo da capa, sem os anéis escuros em volta

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.14-1
- Removida a Música livre (Jamendo e Internet Archive): sai da barra
  lateral, a página, a chave do Jamendo e os downloads. As músicas já
  baixadas continuam na biblioteca como arquivos locais comuns.

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.13-1
- Editar informações da música (menu ⋮ ou lápis na página Informações):
  título, artista, álbum, artista do álbum, faixa, disco, ano, gênero,
  composição e capa
- Arquivos locais: as etiquetas são gravadas no próprio arquivo (por uma cópia
  que substitui o original, sem cortar a música que está tocando). Dá para
  escolher guardar só no Arara Music; músicas de servidor e discos sem
  permissão de gravação ficam assim automaticamente, e a mudança continua
  valendo depois de reindexar ou sincronizar ("Desfazer" volta ao original)

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.12-1
- Capas de álbum certas: a capa é escolhida pela imagem que a maioria das
  faixas usa (capa frontal embutida e cover.jpg da pasta do álbum), em vez da
  primeira faixa lida. Algumas faixas com a imagem de outro disco, ou um
  cover.jpg numa pasta misturada (ex.: Downloads), não trocam mais a capa
- Na primeira abertura os arquivos são relidos uma vez para refazer as capas
- Página do álbum: botão ⋯ (ou clique direito na capa) com "Procurar a capa
  de novo" e "Escolher imagem da capa…"; Preferências > Biblioteca ganhou
  "Refazer capas"
- Informações online (MusicBrainz) só aceitam resultado com o mesmo título e
  o mesmo artista; as respostas antigas em cache são buscadas de novo

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.11-1
- Gêneros do "Sobre o artista" e do álbum agora são clicáveis: abrem a
  página "Similares" com artistas, álbuns e músicas daquele gênero (pastas
  locais e servidores) e artistas para descobrir no MusicBrainz
- Página do artista no mesmo formato da página do álbum: foto, nome e
  "Sobre o artista" fixos à esquerda, álbuns à direita

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.10-1
- Biblioteca em HD externo: o app não trava mais quando o disco está
  bloqueado, desconectado ou acabou de ser desbloqueado (as pastas são
  vigiadas fora da interface)
- Com o disco bloqueado, as músicas continuam na biblioteca em vez de sumir
- Aviso no topo com o botão "Abrir no Arquivos" para desbloquear; ao
  desbloquear, o Arara percebe sozinho e atualiza a biblioteca

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.9-1
- Corrige o app que ficava rodando sem abrir a janela: a janela aparece antes
  de varrer a biblioteca, falar com o GNOME (MPRIS, tema, inibir suspensão) e
  restaurar a última música; nada disso roda mais na thread da interface
- Ao fechar, o processo sai na hora (não fica um Arara invisível para trás)
- Bancos vindos de versões antigas ganham a tabela de análise de transições
- Se a interface travar, um relatório é salvo em ~/.cache/arara-music/travamentos

* Sat Nov 07 2026 Arara Music <noreply@anthropic.com> - 0.7.8-1
- "Sobre o álbum" aparece direto na página do álbum, embaixo da capa e dos
  botões (ou embaixo das faixas em janelas estreitas)
- A barra "Sobre o artista" já abre sozinha quando há espaço
- Lançamento do álbum mostra a data original, como na Wikipédia

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
