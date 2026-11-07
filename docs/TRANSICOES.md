# Transições entre músicas

Preferências › Reprodução › **Transição entre músicas**. Pesquisa feita em players
de código aberto e o que entrou no Arara (0.7.6).

| Método | Onde existe | No Arara |
|---|---|---|
| Gapless (próxima pré-carregada) | Quod Libet, Rhythmbox, mpv `--gapless-audio`, Strawberry | **Sem intervalo**: o segundo deck abre a próxima música antes e entra quando a atual acaba |
| Crossfade com duração fixa | Strawberry, Clementine, Audacious, MPD `crossfade` | **Crossfade**, 1–12 s |
| Curvas de fade | Mixxx (curva do crossfader), DAWs | Suave (potência constante), Linear, Curva S, DJ |
| Fade ao trocar manualmente / ao pausar | Strawberry, Audacious | Crossfade curto (até 2 s) ao pular; fade de 0,2 s ao pausar e 0,3 s ao retomar |
| Não misturar faixas do mesmo álbum | Strawberry | **Álbuns sem crossfade**: faixas seguidas do mesmo álbum tocam sem intervalo |
| Pular silêncio | Audacious (crossfade), Mixxx Auto DJ "Skip Silence" | Análise acha o primeiro e o último som da faixa |
| MixRamp (sobrepor só as partes calmas) | MPD `mixrampdb`/`mixrampdelay` | **Mixagem inteligente**: a próxima chega ao volume normal quando a atual cai abaixo dele; transições curtas para finais secos, longas para fade-outs |
| Alinhar na batida | Mixxx Auto DJ (beatgrid + sync) | Experimental: quando os andamentos batem (±4 %, ou dobro/metade), a transição começa numa batida e a próxima entra na sua primeira batida. Sem time-stretch |
| Volume igualado | ReplayGain 2 / rsgain (EBU R128) | Músicas sem tags de ganho têm a loudness medida e vão para −18 LUFS |

Ficou de fora: beatmatching com mudança de andamento (time-stretch) e cortes por
intro/outro marcados à mão (Mixxx), porque o QtMultimedia não permite processar o
áudio em tempo real.

## Como funciona

- `arara-core/src/analysis.rs` decodifica a faixa (Symphonia) e mede, em blocos de 10 ms:
  silêncio (< −55 dBFS), rampas de entrada e saída (6 dB abaixo do nível típico),
  loudness integrada (EBU R128) e andamento/primeira batida (autocorrelação do
  envelope de ataques). Leva cerca de 0,2 s numa música de 4 minutos; o resultado fica na tabela
  `track_analysis` e só é refeito se o arquivo mudar.
- Só a música atual e a próxima são analisadas; músicas de servidores não são
  (seria preciso baixar o arquivo inteiro) e usam o crossfade comum.
- `qml/ui/Decks.qml` tem dois `MediaPlayer` ("decks"). Um toca, o outro carrega a
  próxima. O `xf` em `Main.qml` decide quando e como a próxima entra.
- A velocidade de reprodução vale para os dois decks; a duração do fade é em
  tempo de relógio.

`arara analyze <arquivo>` mostra a análise de uma música. `arara-music
--debug-transitions` registra cada transição no terminal.
