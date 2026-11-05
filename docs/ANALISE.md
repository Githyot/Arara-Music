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

## Próximos passos

1. Página de artistas, playlists, fila editável e favoritos (as tabelas já existem).
2. MPRIS (controle pela barra do GNOME e teclas de mídia) e integração com o portal de configurações (cor de destaque e tema em tempo real).
3. Trocar o JSON de álbuns por um `QAbstractListModel` em Rust, para acervos com mais de 50 mil faixas.
4. Monitorar a pasta com inotify (rescan instantâneo ao adicionar músicas).
5. Editor de letras e envio de letras sincronizadas para o LRCLIB.
6. Jellyfin/Subsonic (o núcleo já separa índice e fonte).
7. Empacotamento Flatpak.
