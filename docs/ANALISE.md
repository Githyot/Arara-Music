# Análise do Nocturne e plano do Arara Music

## Por que o Nocturne gasta 7,1 GB de RAM

Lendo o código (`src/integrations/local.py` e `models.py`), o consumo vem de três decisões:

1. **Duas texturas de capa por música, não por álbum.** No scan, `verifySong()` chama `updateCoverArt()` para *cada faixa*. Ela abre a imagem embutida com Pillow, redimensiona para 720 px e 240 px e cria dois `Gdk.Texture` (`gdkPaintableBig` e `gdkPaintable`). Uma textura RGBA de 720×720 ocupa uns 2 MB e a de 240×240 uns 230 KB. Com 3.000 músicas dá cerca de 6,9 GB, que bate com a captura de tela. Um álbum de 12 faixas guarda a mesma capa 12 vezes.
2. **Nada é liberado.** Todos os modelos ficam em `self.loaded_models` (um dict com todas as músicas, álbuns e artistas como `GObject`), com as texturas, enquanto o app estiver aberto.
3. **Python + GObject por item.** Cada música é um `GObject` com ~25 propriedades e listas Python, o que custa muito mais que uma linha num banco.

## Por que demora para abrir e catalogar

- **Não existe índice salvo.** A cada abertura, `on_login()` roda `rglob("*")` na pasta inteira e lê as tags de *todos* os arquivos de novo com TinyTag. O SQLite guarda só favoritos, notas e scrobbles.
- **SQLite aberto e fechado por música.** `verifySong()` abre uma conexão e lê a tabela `stars` inteira para cada faixa, e `get_rating()` abre mais uma. Num acervo de 10 mil músicas são mais de 20 mil conexões.
- **Decodificar e redimensionar capas (Pillow) no caminho crítico**, duas vezes por faixa.
- `ThreadPoolExecutor` em Python não paraleliza CPU por causa do GIL.

## Letras

O Nocturne até consulta o LRCLIB, mas só por `/api/get` (busca exata). Se título, artista, álbum ou duração não batem, desiste. Ele só sincroniza por linha e não entende LRC estendido com tempo por palavra, então não tem modo karaokê.

## Layout

O layout do Nocturne é bom e já é GNOME de verdade: usa libadwaita (`AdwNavigationSplitView`, `AdwBottomSheet`, breakpoints adaptativos). O problema é desempenho, não visual. Como você escolheu Qt, o Arara Music imita o Adwaita à mão: paleta oficial clara e escura, header bar desenhada pelo próprio app (CSD) com botão de fechar, sidebar de navegação, cards com cantos de 12 px, botão azul "suggested" e tipografia Adwaita Sans/Cantarell. Um limite que fica: o Qt não lê o tema nem a cor de destaque do GNOME sozinho. Por enquanto lemos claro/escuro pelo `gsettings`.

## Como o Arara Music resolve

| Problema | Solução |
|---|---|
| Capas em RAM | Capa extraída **uma vez por álbum**, gravada em disco como JPEG de 256 e 640 px (cache endereçado por hash, capas iguais são deduplicadas). A interface carrega só as capas visíveis, em thread separada (`Image { asynchronous; sourceSize; cache: false }`), e o GridView recicla os delegates. |
| Reescanear tudo a cada abertura | O índice fica em SQLite (WAL). Na abertura a interface lê do banco na hora e faz um rescan incremental em segundo plano, que só lê arquivos cujo `mtime`/tamanho mudou. |
| Scan lento | Tags lidas com `lofty` em paralelo de verdade (rayon). As gravações acontecem numa única transação. |
| Busca | FTS5 com remoção de acentos ("cancao" acha "Canção"). |
| Letras | Ordem de busca: cache no banco, depois `.lrc`/`.txt` ao lado do arquivo, tag embutida, LRCLIB `/get` e, por último, LRCLIB `/search` com escolha pela duração mais próxima. Resultado negativo também fica em cache por 7 dias. |
| Karaokê | Parser de LRC estendido (`<mm:ss.xx>` por palavra). Quando o LRC é só por linha, o tempo das palavras é interpolado. A palavra vai sendo preenchida com a cor de destaque enquanto é cantada, e clicar numa linha pula para aquele trecho. |

## Medições (biblioteca sintética: 2.000 MP3 em 200 álbuns, capas de 1000×1000 embutidas, 4 núcleos)

| | Arara Music |
|---|---|
| Primeiro scan (sem cache) | 1,3 s, pico de 80 MB |
| Reabrir sem mudanças | 10 ms (2.000 arquivos verificados) |
| Reabrir com 10 arquivos alterados | 14 ms |
| Abrir o banco e listar álbuns | < 1 ms |
| Cache de capas em disco | 17 MB |
| Banco | 0,9 MB |
| App aberto (memória privada, `RssAnon`) | 76 a 95 MB com OpenGL por software (llvmpipe); 21 MB com `QT_QUICK_BACKEND=software` |
| Depois de rolar a grade inteira | +2 MB (as capas não se acumulam) |

Não rodei o Nocturne aqui com a mesma biblioteca. A comparação é com os 7,1 GB da sua captura, e o número exato do Nocturne depende do tamanho do seu acervo.

## Feito na versão 0.2

- Artistas (avatares redondos), página do artista, favoritas, tocadas recentemente e playlists (criar, renomear, excluir, adicionar e remover músicas)
- Menu ⋮ por música: tocar a seguir, adicionar à fila, adicionar à playlist, ir para o álbum
- Fila na tela "Tocando agora" (aba Fila), aleatório, repetir tudo/uma, volume; fila, posição e modo de repetição restaurados ao reabrir
- MPRIS 2: aparece nos controles de mídia do GNOME e responde às teclas de mídia (testado via D-Bus: Play/Pause, SetPosition, metadados com capa)
- Monitoramento da pasta: copiar um álbum para a pasta faz ele aparecer em ~2 s, sem rescan completo
- Tema escuro e cor de destaque lidos do portal `org.freedesktop.appearance` e atualizados ao vivo
- Manifesto Flatpak, arquivo .desktop, metainfo e ícone

## Feito na versão 0.3

- **Ícones simbólicos do Adwaita** (SVG empacotados no app, tingidos pela cor do tema) no lugar dos caracteres Unicode.
- **Ordenação natural** de artistas e álbuns ("Artista 2" antes de "Artista 10"), via collation SQLite própria.
- **Arrastar para reordenar** a fila e as playlists.
- **Editor de letras**: colar o texto, sincronizar tocando a música e apertando Enter no início de cada verso (Backspace desfaz, ← volta 5 s), salvar no banco e, se quiser, como `.lrc` ao lado do arquivo, e **enviar ao LRCLIB** (com a prova de trabalho que a API exige). O envio não foi testado aqui porque a rede desta máquina bloqueia o LRCLIB.
- **Lista de músicas nativa** (`QAbstractListModel` em Rust): a aba Músicas e a busca não criam mais um objeto JavaScript por faixa.
- **Servidores remotos: Navidrome/Subsonic e Jellyfin.** O catálogo do servidor é espelhado no mesmo índice local, então busca, favoritas, playlists, letras e fila funcionam igual às músicas locais, a biblioteca remota abre na hora e dá para navegar mesmo com o servidor fora do ar. A sincronização baixa o catálogo em páginas de 500 (poucas requisições, não uma por álbum), baixa cada capa uma vez para o mesmo cache em disco e, nas próximas vezes, só regrava as faixas cujos metadados mudaram. Só o token derivado fica salvo (token MD5 com sal no Subsonic, token de acesso no Jellyfin), nunca a senha.
- Correção: álbuns cuja primeira faixa lida não tinha capa ficavam sem capa mesmo quando outra faixa tinha.

## Medições com 50 mil faixas (500 artistas, 5.000 álbuns, capa embutida na faixa 1 de cada álbum)

| | Arara Music |
|---|---|
| Primeiro scan (sem cache) | 4,1 s, pico de 53 MB |
| Reabrir sem mudanças | 0,2 s (50.000 arquivos verificados) |
| Abrir o banco e listar os 5.000 álbuns | 13 ms |
| Banco / cache de capas | 20 MB / 3,7 MB |
| Janela aberta | 0,23 s |
| App aberto (`RssAnon`) | 134 MB; 138 MB depois de rolar 300 vezes pela grade de álbuns; 168 MB com a aba Músicas aberta e rolada (50 mil linhas) |

Servidor remoto simulado (`tools/mock_server.py`, API do Jellyfin) com 17.884 faixas e 1.910 capas: primeira sincronização em 3,0 s, sincronizações seguintes sem mudanças em 0,2 s.

## Feito na versão 0.4

**Apple Music e YouTube Music.** Tocar as músicas desses serviços dentro do Arara não é viável de forma limpa: o Apple Music entrega o áudio com DRM (só toca nos apps da Apple ou num navegador com Widevine, o que exigiria embutir um Chromium) e o YouTube Music não tem API, só extração por engenharia reversa, contra os termos de uso. O que foi feito é trazer a *coleção*: o Arara lê a exportação da biblioteca do Apple Music (`Library.xml`), o Google Takeout do YouTube Music e CSVs de Exportify/TuneMyMusic/Soundiiz/M3U/XSPF, procura cada música na biblioteca (locais e servidores) ignorando acentos, "(Remastered)", "[Official Video]", "feat." e escolhendo a versão de duração mais próxima, cria as playlists, marca as curtidas como favoritas e lista o que falta. Reimportar substitui a playlist em vez de duplicar.

**Auditoria de bugs e o que foi corrigido:**

| Problema encontrado | Correção |
|---|---|
| Em janelas estreitas (< 620 px) a barra lateral sumia e não havia como navegar | Botão de barra lateral no cabeçalho, que abre a barra por cima do conteúdo |
| Grade de álbuns ficava com uma coluna só em telas estreitas | Mínimo de duas colunas, capas encolhem |
| Títulos das músicas cortados cedo em janelas estreitas | Largura do texto calculada pelo espaço livre |
| Botão "voltar" aparecia em páginas de primeiro nível (playlist, servidor) | Só aparece quando há para onde voltar |
| Álbum aberto a partir de um servidor destacava "Álbuns" na barra lateral | A barra lateral destaca a seção de origem |
| Música que não abre (arquivo apagado, servidor fora do ar) parava tudo em silêncio | Aviso na tela e pula para a próxima (no máximo 3 seguidas) |
| Volume voltava a 100% a cada abertura | Volume salvo |
| ReplayGain era lido das tags mas nunca aplicado | Aplicado (faixa, ou álbum quando a faixa não tem), com opção no menu |
| Não havia como trocar a pasta de músicas | Menu principal: pasta de músicas, reindexar, importar, atalhos, sobre |
| Remover um servidor deixava as músicas dele na fila | Saem da fila também |
| Diálogo de arquivo do Qt é estranho ao GNOME | Usa o seletor nativo do GNOME pelo portal (funciona no Flatpak); o do Qt fica só de reserva |

## Próximos passos

1. Equalizador, temporizador para dormir e transição sem pausa (gapless).
2. Guardar os tokens dos servidores no chaveiro do GNOME (Secret Service) em vez do banco.
3. Cache de áudio para ouvir músicas do servidor offline, e transcodificação opcional para conexões lentas.
4. Testar com Navidrome e Jellyfin de verdade (aqui foi usado um servidor simulado, porque a rede desta máquina só alcança o próprio computador).
5. Testar o Flatpak em uma máquina com flatpak-builder (aqui não deu para rodar).
