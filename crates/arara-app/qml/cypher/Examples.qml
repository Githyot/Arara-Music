pragma Singleton
import QtQuick
import Qt.labs.settings
import AraraCypher
import io.github.arara as Arara

// Músicas de exemplo, só com informação musical (acordes, formas, seções e
// batida). A letra e a melodia ficam de fora de propósito: têm direitos autorais.
// No passo 2 isto vira o formato de arquivo de verdade da biblioteca.
//
// Formato de cada música:
//   strums    lista de batidas; cada parte escolhe uma com "strum: n" (padrão 0).
//             Códigos de cada tempo: veja StrumTab.qml.
//   voicings  formas tiradas da aula: { "Acorde": { frets, fingers } }, com as
//             cordas do Mi grave ao Mi agudo (-1 = não toca, 0 = solta).
//             Quando o mesmo acorde aparece com duas formas, a segunda leva um
//             apelido depois de "@" (ex.: "Gm7@2"); o "@..." não aparece na tela.
//             Acorde sem forma aqui usa a forma calculada pelo app.
QtObject {
    id: examples
    // Exemplos que a pessoa excluiu da lista (pelo título). Ficam excluídos ao
    // reabrir o app; "Restaurar exemplos" em Ajustes traz de volta.
    property string hiddenJson: "[]"
    property Settings _settings: Settings {
        category: "cypher-examples"
        property alias hidden: examples.hiddenJson
    }
    readonly property var hidden: { try { return JSON.parse(hiddenJson) } catch (e) { return [] } }
    readonly property var visibleSongs: songs.filter(function (s) { return hidden.indexOf(s.title) < 0 })
    function hideExample(song) {
        if (!song || hidden.indexOf(song.title) >= 0) return
        hiddenJson = JSON.stringify(hidden.concat([song.title]))
    }
    function restoreExamples() { hiddenJson = "[]" }
    // Exemplos excluídos também deixam de valer para as músicas da biblioteca.
    onVisibleSongsChanged: Arara.CypherLibrary.setExamples(JSON.stringify(visibleSongs))

    // Ligação com o Arara Music: acha a faixa da biblioteca de uma cifra
    // (function(sheet) -> faixa ou null) e pede o modo Estudar.
    property var trackFinder: null
    signal studyRequested(var track, var sheet)

    // Toques copiados no editor visual da tab (vale entre as partes).
    property var tabClip: []

    // ---- Golpes da batida ----
    // "B" baixo, "D" tudo, "d" acorde sem o baixo, "U" agudas para cima,
    // "X" abafado para baixo, "XU" abafado para cima, "" pausa e, para dedilhado, "P" + cordas ("P03" = cordas 0
    // e 3 para baixo, "P5U" = corda 5 para cima). Corda 0 = Mi grave.
    // Palhetada forte (acento): o mesmo golpe com ">" no fim ("D>", "U>", "B>").
    function isAccent(code) { return !!code && code.charAt(code.length - 1) === ">" }
    function plain(code) { return isAccent(code) ? code.substring(0, code.length - 1) : (code || "") }
    function withAccent(code, on) { var p = plain(code); return p === "" ? "" : on ? p + ">" : p }
    function isPick(code) { code = plain(code); return code && code.charAt(0) === "P" }
    function isMute(code) { code = plain(code); return code === "X" || code === "XU" }
    function strokeUp(code) {
        code = plain(code)
        return code === "U" || code === "XU" || (isPick(code) && code.charAt(code.length - 1) === "U")
    }
    // Forte: seta dupla (⇓ ⇑), mais grossa, para ler de longe.
    function strokeArrow(code) {
        var a = isAccent(code)
        code = plain(code)
        if (code === "") return "·"
        var up = strokeUp(code)
        var arrow = a ? (up ? "⬆" : "⬇") : (up ? "↑" : "↓")
        return isMute(code) ? arrow + "×" : arrow
    }
    function strokeLabel(code) {
        var a = isAccent(code)
        code = plain(code)
        var l = isPick(code) ? "corda " + pickStrings(code).map(function (s) { return ["E", "A", "D", "G", "B", "e"][s] }).join("+")
              : ({ "": "·", "B": "baixo", "D": "tudo", "d": "acorde", "U": "agudas", "X": "abafa ↓", "XU": "abafa ↑" })[code] || code
        return a ? l + " forte" : l
    }
    function pickStrings(code) {
        var out = []
        for (var i = 1; i < code.length; ++i) {
            var n = code.charCodeAt(i) - 48
            if (n >= 0 && n <= 5) out.push(n)
        }
        return out
    }
    function pickCode(strings, up) {
        strings = strings.slice().sort()
        return strings.length ? "P" + strings.join("") + (up ? "U" : "") : ""
    }
    // Cordas que soam num tempo, para uma forma { frets, root }.
    function strokeStrings(shape, code) {
        if (!shape) return []
        code = plain(code)
        if (isPick(code)) return pickStrings(code).filter(function (s) { return shape.frets[s] >= 0 })
        var played = []
        for (var s = 0; s < 6; ++s) if (shape.frets[s] >= 0) played.push(s)
        var upper = played.filter(function (s) { return s > shape.root })
        return code === "B" ? (shape.frets[shape.root] >= 0 ? [shape.root] : [])
             : code === "D" ? played
             : code === "d" || code === "X" ? upper
             : code === "U" || code === "XU" ? played.slice(-3) : []
    }
    // Contagem de uma batida com n tempos e "per" tempos por batida do compasso.
    function countsFor(n, per) {
        var marks = per === 3 ? ["e", "a"] : per === 4 ? ["e", "&", "a"] : ["e"]
        var out = []
        for (var i = 0; i < n; ++i) out.push(i % per === 0 ? String(Math.floor(i / per) % 4 + 1) : marks[i % per - 1])
        return out
    }

    // Nome que aparece na tela (sem o apelido "@...").
    // Reescreve os toques da tab marcados com esse acorde (até o próximo
    // acorde marcado) com as casas da forma nova: cada nota fica na mesma
    // corda e pega a casa da forma; corda que a forma não toca sai do toque.
    // Abafadas (x) e notas com técnica ficam como estão. Devolve o texto novo
    // e quantos toques mudaram: { tab, changed }.
    function applyShapeToTab(tab, token, frets) {
        if (!tab) return { tab: tab, changed: 0 }
        var systems = JSON.parse(Arara.CypherMusic.tabModel(tab))
        var cur = "", changed = 0
        for (var s = 0; s < systems.length; ++s) {
            var sys = systems[s]
            var marks = (sys.chords || []).slice().sort(function (a, b) { return a.at - b.at })
            var m = 0
            for (var e = 0; e < sys.events.length; ++e) {
                while (m < marks.length && marks[m].at <= e) { cur = marks[m].name; m++ }
                if (cur !== token) continue
                var ev = sys.events[e], out = [], diff = false
                for (var k = 0; k < ev.notes.length; ++k) {
                    var n = ev.notes[k]
                    if (n.fret === 255 || n.tech) { out.push(n); continue }
                    var f = frets[n.string]
                    if (f === undefined || f < 0) { diff = true; continue }
                    if (f !== n.fret) diff = true
                    out.push({ string: n.string, fret: f })
                }
                if (diff && out.length) { ev.notes = out; changed++ }
            }
        }
        return { tab: changed ? Arara.CypherMusic.renderTab(JSON.stringify(systems)) : tab, changed: changed }
    }

    function chordName(token) {
        var at = token.indexOf("@")
        return at < 0 ? token : token.substring(0, at)
    }

    // Forma da aula para esse acorde dessa música, ou null.
    function voicing(song, token) {
        if (!song || !song.voicings) return null
        return song.voicings[token] || null
    }

    // Batida de uma parte.
    function strumOf(song, section) {
        if (!song || !song.strums || song.strums.length === 0) return null
        var i = section && section.strum !== undefined ? section.strum : 0
        return song.strums[i] || song.strums[0]
    }

    // Forma para desenhar: { frets, fingers, base, root }.
    // Com forma da aula e sem transposição, usa a da aula. Transpondo, a forma
    // da aula só anda pelo braço se não tiver corda solta; senão o app calcula.
    function blankShape() {
        return { frets: [-1, -1, -1, -1, -1, -1], fingers: [0, 0, 0, 0, 0, 0], base: 1, root: 0 }
    }
    function shape(chord, semitones, v) {
        if (v) {
            var shift = ((semitones % 12) + 12) % 12
            var frets = v.frets.slice()
            var ok = true
            if (shift !== 0) {
                var hasOpen = frets.indexOf(0) >= 0
                var hi = -1, lo = 99
                for (var i = 0; i < 6; ++i) {
                    if (frets[i] > 0) { hi = Math.max(hi, frets[i]); lo = Math.min(lo, frets[i]) }
                }
                var d = shift
                if (hi + d > 15) d -= 12
                if (hasOpen || lo + d < 1 || hi + d > 15) ok = false
                else for (var j = 0; j < 6; ++j) if (frets[j] > 0) frets[j] += d
            }
            if (ok) {
                var max = 0, min = 99, root = -1
                for (var k = 0; k < 6; ++k) {
                    if (frets[k] >= 0 && root < 0) root = k
                    if (frets[k] > 0) { max = Math.max(max, frets[k]); min = Math.min(min, frets[k]) }
                }
                return {
                    frets: frets,
                    fingers: v.fingers || [0, 0, 0, 0, 0, 0],
                    base: max <= 4 ? 1 : min,
                    root: v.root !== undefined ? v.root : Math.max(0, root)
                }
            }
        }
        var json = Arara.CypherMusic.chordShape(chordName(chord), semitones)
        return json.length ? JSON.parse(json) : null
    }

    // Nota escrita na pauta (uma oitava acima do som), soletrada pelo grau
    // dentro do acorde: em D7b9 sai Fá♯ e Mi♭, não Sol♭ e Ré♯.
    // Devolve { step, acc }: passo diatônico (Dó0 = 0) e acidente (-1, 0, 1).
    function spell(midi, chordName) {
        var written = midi + 12
        var pc = written % 12
        var letterPc = [0, 2, 4, 5, 7, 9, 11]
        var li = "CDEFGAB".indexOf(chordName.charAt(0))
        var fallback = function () {
            var flat = chordName.charAt(1) === "b"
            var L = flat ? [0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6] : [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
            var A = flat ? [0, -1, 0, -1, 0, 0, -1, 0, -1, 0, -1, 0] : [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
            return { step: L[pc] + 7 * (Math.floor(written / 12) - 1), acc: A[pc] }
        }
        if (li < 0) return fallback()
        var rootPc = letterPc[li]
        if (chordName.charAt(1) === "#") rootPc += 1
        else if (chordName.charAt(1) === "b") rootPc -= 1
        rootPc = (rootPc + 12) % 12
        // Semitons acima da fundamental -> grau (0 = fundamental, 1 = 9ª/2ª...).
        var degree = [0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6]
        var off = (pc - rootPc + 12) % 12
        var letter = (li + degree[off]) % 7
        var acc = pc - letterPc[letter]
        if (acc > 6) acc -= 12
        if (acc < -6) acc += 12
        if (acc < -1 || acc > 1) return fallback()
        var natural = written - acc
        return { step: letter + 7 * (Math.floor(natural / 12) - 1), acc: acc }
    }

    readonly property var songs: [
        {
            title: "I Feel So Good Today",
            artist: "Charlie Brown Jr.",
            key: "C#",
            video: "https://www.youtube.com/watch?v=GZgcJF1Ef0A",
            source: "Formas e batidas da videoaula do canal Cifra Music",
            strums: [
                {
                    name: "Intro e partes A: tudo para baixo, em colcheias",
                    pattern: ["D", "D", "D", "D", "D", "D", "D", "D"],
                    counts: ["1", "e", "2", "e", "3", "e", "4", "e"]
                },
                {
                    name: "Parte B: ↓ ↓ ↑ ↓ ↑ ↓ ↓",
                    pattern: ["D", "", "D", "U", "D", "U", "D", "D"],
                    counts: ["1", "e", "2", "e", "3", "e", "4", "e"]
                }
            ],
            voicings: {
                "Fm7": { frets: [-1, 8, 6, 8, -1, -1], fingers: [0, 3, 1, 4, 0, 0] },
                "C#5@A": { frets: [-1, 4, 6, 5, -1, -1], fingers: [0, 1, 3, 2, 0, 0] },
                "Bb9(7)": { frets: [6, -1, 6, 5, -1, -1], fingers: [2, 0, 3, 1, 0, 0] },
                "F#5(9)": { frets: [2, 4, 6, -1, -1, -1], fingers: [1, 3, 4, 0, 0, 0] },
                "C#5": { frets: [-1, 4, 6, 6, -1, -1], fingers: [0, 1, 3, 4, 0, 0] },
                "G#5": { frets: [4, 6, 6, -1, -1, -1], fingers: [1, 3, 4, 0, 0, 0] },
                "F5": { frets: [1, 3, 3, -1, -1, -1], fingers: [1, 3, 4, 0, 0, 0] },
                "Bb5": { frets: [-1, 1, 3, 3, -1, -1], fingers: [0, 1, 3, 4, 0, 0] },
                "F#5": { frets: [2, 4, 4, -1, -1, -1], fingers: [1, 3, 4, 0, 0, 0] }
            },
            sections: [
                { name: "Intro", repeat: 5, chords: ["Fm7", "C#5@A", "Bb9(7)", "F#5(9)"] },
                { name: "Parte A", repeat: 1, chords: ["Fm7", "C#5@A", "Bb9(7)", "F#5(9)"] },
                { name: "Parte B", repeat: 1, strum: 1, chords: ["C#5", "G#5", "F5", "Bb5", "G#5"] },
                { name: "Solo (riff)", repeat: 1, chords: [],
                  note: "O solo é um riff de notas soltas, não acordes. A tab está na videoaula em 2:53. Para guardar no app, toque em Editar e cole a tab na parte Solo da sua cópia." },
                { name: "Parte A (variação)", repeat: 1, chords: ["Fm7", "F#5", "Bb9(7)", "F#5(9)", "Fm7", "C#5@A", "Bb9(7)", "F#5(9)"] },
                { name: "Parte B", repeat: 1, strum: 1, chords: ["C#5", "G#5", "F5", "Bb5", "G#5"] },
                { name: "Final", repeat: 1, chords: ["Fm7", "C#5@A", "Bb9(7)", "F#5(9)", "Fm7", "C#5@A", "Bb9(7)"] }
            ]
        },
        {
            title: "Yukon",
            artist: "Justin Bieber",
            key: "Gm",
            video: "https://www.youtube.com/shorts/j3ASgHUkAqM",
            source: "Formas do short de guitarra enviado pelo HP (sem capotraste)",
            strums: [
                {
                    name: "Batida: R&B suave (sugestão)",
                    pattern: ["B", "", "d", "U", "", "U", "d", "U"],
                    counts: ["1", "e", "2", "e", "3", "e", "4", "e"]
                },
                {
                    name: "Oitava: as duas notas juntas, deixando soar",
                    pattern: ["D", "", "", "", "D", "", "", ""],
                    counts: ["1", "e", "2", "e", "3", "e", "4", "e"]
                }
            ],
            // Pestana nas quatro cordas de cima, baixo no Mi grave e Lá abafada.
            voicings: {
                "Cm7": { frets: [8, -1, 8, 8, 8, 8], fingers: [2, 0, 1, 1, 1, 1] },
                "Dm7": { frets: [10, -1, 10, 10, 10, 10], fingers: [2, 0, 1, 1, 1, 1] },
                "Gm7": { frets: [3, -1, 3, 3, 3, 3], fingers: [2, 0, 1, 1, 1, 1] },
                "C@oitava": { frets: [-1, -1, 10, -1, 13, -1], fingers: [0, 0, 1, 0, 4, 0] }
            },
            sections: [
                { name: "Intro", repeat: 1, chords: ["Cm7", "Dm7", "Gm7", "Cm7", "Dm7", "Gm7"] },
                { name: "Passagem (oitava de Dó)", repeat: 1, strum: 1, chords: ["C@oitava", "Gm7"] },
                { name: "Verso", repeat: 1, chords: ["Cm7", "Dm7", "Gm7", "Cm7", "Dm7", "Gm7", "Cm7"] },
                { name: "Pré-refrão", repeat: 1, chords: ["Dm7", "Gm7", "Cm7", "Dm7", "Gm7", "Cm7", "Dm7", "Gm7"] },
                { name: "Refrão", repeat: 2, chords: ["Cm7", "Dm7", "Gm7"] },
                { name: "Verso 2", repeat: 2, chords: ["Cm7", "Dm7", "Gm7"] },
                { name: "Pré-refrão", repeat: 1, chords: ["Dm7", "Gm7", "Cm7", "Dm7", "Gm7", "Cm7", "Dm7", "Gm7"] },
                { name: "Refrão", repeat: 2, chords: ["Cm7", "Dm7", "Gm7"] },
                { name: "Final", repeat: 1, strum: 1, chords: ["C@oitava", "Gm7"] }
            ]
        },
        {
            title: "The Only Exception",
            artist: "Paramore",
            key: "B",
            source: "Cifra e formas enviadas pelo HP",
            strums: [
                {
                    name: "Batida: balada (sugestão)",
                    pattern: ["B", "", "d", "U", "", "U", "d", "U"],
                    counts: ["1", "e", "2", "e", "3", "e", "4", "e"]
                }
            ],
            voicings: {
                "Badd4": { frets: [7, 9, 9, 8, 0, 0], fingers: [1, 3, 4, 2, 0, 0] },
                "F#m7": { frets: [-1, 9, 11, 11, 10, 0], fingers: [0, 1, 3, 4, 2, 0] },
                "Emaj7": { frets: [-1, 7, 9, 8, 0, 0], fingers: [0, 1, 3, 2, 0, 0] },
                "F#m11": { frets: [2, -1, 2, 2, 0, 0], fingers: [1, 0, 2, 3, 0, 0] },
                "E": { frets: [0, 2, 2, 1, 0, 0], fingers: [0, 2, 3, 1, 0, 0] },
                "C#m7": { frets: [9, -1, 9, 9, 0, 0], fingers: [1, 0, 2, 3, 0, 0] },
                "F#7": { frets: [2, 4, 4, 3, 0, 0], fingers: [1, 3, 4, 2, 0, 0] }
            },
            sections: [
                { name: "Intro", repeat: 2, chords: ["Badd4", "F#m7", "Emaj7"] },
                { name: "Verso", repeat: 4, chords: ["Badd4", "F#m7", "Emaj7"] },
                { name: "Refrão", repeat: 2, chords: ["Badd4", "F#m11", "E"] },
                { name: "Passagem", repeat: 1, chords: ["Badd4"] },
                { name: "Verso 2", repeat: 4, chords: ["Badd4", "F#m7", "Emaj7"] },
                { name: "Refrão", repeat: 2, chords: ["Badd4", "F#m11", "E"] },
                { name: "Ponte", repeat: 4, chords: ["C#m7", "Badd4", "F#7"] },
                { name: "Refrão final", repeat: 1, note: "Entra com um E antes", chords: ["E", "Badd4", "F#m11", "E"] },
                { name: "Refrão final (repete)", repeat: 3, chords: ["Badd4", "F#m11", "E"] },
                { name: "Final", repeat: 1, chords: ["F#m11", "E", "Badd4", "F#m11", "E", "Badd4"] }
            ]
        },
        {
            title: "Going Home",
            artist: "Arranjo de violão de @torrance.dylan",
            key: "F",
            video: "https://www.youtube.com/watch?v=AvpeYxiqsi8",
            source: "Acordes e formas da tab do vídeo enviado pelo HP · na parte B o tom sobe para Lá♭",
            strums: [
                {
                    name: "Dedilhado: baixo e acorde (cada acorde dura 2 tempos)",
                    pattern: ["B", "d", "U", "d"],
                    counts: ["1", "e", "2", "e"]
                },
                {
                    name: "Final: acorde arpejado, deixando soar",
                    pattern: ["B", "d", "", ""],
                    counts: ["1", "e", "2", "e"]
                }
            ],
            voicings: {
                "Fmaj9": { frets: [-1, 8, 5, 5, 5, -1], fingers: [0, 4, 1, 1, 1, 0] },
                "C/Bb": { frets: [6, -1, 5, 5, 5, -1], fingers: [2, 0, 1, 1, 1, 0] },
                "Am7": { frets: [5, -1, 5, 5, -1, -1], fingers: [1, 0, 2, 3, 0, 0] },
                "D7b9": { frets: [-1, 5, 4, 5, 4, -1], fingers: [0, 3, 1, 4, 2, 0] },
                "Gm7": { frets: [3, -1, -1, 3, 3, 5], fingers: [1, 0, 0, 2, 3, 4] },
                "A7b13": { frets: [-1, 0, 5, 6, 6, 5], fingers: [0, 0, 1, 3, 4, 2] },
                "Dm7": { frets: [-1, 5, 7, 5, 6, -1], fingers: [0, 1, 3, 1, 2, 0] },
                "Dbm7": { frets: [-1, 4, 6, 4, 5, -1], fingers: [0, 1, 3, 1, 2, 0] },
                "Db7": { frets: [-1, 4, 6, 4, 6, -1], fingers: [0, 1, 3, 1, 4, 0] },
                "Cm7": { frets: [-1, 3, 5, 3, 4, -1], fingers: [0, 1, 3, 1, 2, 0] },
                "Cm11": { frets: [-1, 3, -1, 3, 6, -1], fingers: [0, 1, 0, 2, 4, 0] },
                "F13b9": { frets: [-1, 8, 7, 8, 7, -1], fingers: [0, 3, 1, 4, 2, 0] },
                "Bbmaj7": { frets: [6, -1, 7, 7, 6, -1], fingers: [1, 0, 3, 4, 2, 0] },
                "Dm7@2": { frets: [-1, -1, 0, 5, 6, 5], fingers: [0, 0, 0, 1, 2, 1] },
                "G13": { frets: [3, -1, 3, 4, 5, 5], fingers: [1, 0, 2, 3, 4, 4] },
                "Gm7@2": { frets: [3, -1, 3, 3, 6, -1], fingers: [1, 0, 1, 1, 4, 0] },
                "C7sus": { frets: [-1, 3, 3, 3, 6, -1], fingers: [0, 1, 1, 1, 4, 0] },
                "Bb/C": { frets: [8, -1, 8, 7, 6, -1], fingers: [3, 0, 4, 2, 1, 0] },
                "Gb/C": { frets: [8, -1, 8, 6, 7, -1], fingers: [3, 0, 4, 1, 2, 0] },
                "Bbm7": { frets: [6, -1, 6, 6, 6, -1], fingers: [1, 0, 1, 1, 1, 0] },
                "Eb7sus": { frets: [-1, 6, 6, 6, 6, -1], fingers: [0, 1, 1, 1, 1, 0] },
                "Eb7b9": { frets: [-1, 6, 5, 6, 5, -1], fingers: [0, 3, 1, 4, 2, 0] },
                "Abmaj7": { frets: [4, -1, 5, 5, 4, -1], fingers: [1, 0, 3, 4, 2, 0] },
                "Fm7": { frets: [4, -1, -1, 1, 1, 3], fingers: [4, 0, 0, 1, 1, 3] },
                "B13": { frets: [7, -1, 7, 8, 9, -1], fingers: [1, 0, 2, 3, 4, 0] },
                "Gm9": { frets: [3, -1, -1, 3, 3, 5], fingers: [1, 0, 0, 2, 3, 4] },
                "C13b9": { frets: [-1, 3, 2, 3, 2, -1], fingers: [0, 3, 1, 4, 2, 0] },
                "Dbmaj7": { frets: [-1, 4, 6, 5, 6, 4], fingers: [0, 1, 3, 2, 4, 1] },
                "Eb7sus@2": { frets: [-1, 6, -1, 6, 6, 6], fingers: [0, 1, 0, 1, 1, 1] },
                "Fmaj7": { frets: [1, -1, 2, 2, 1, -1], fingers: [1, 0, 3, 4, 2, 0] }
            },
            sections: [
                { name: "Tema", repeat: 1, chords: ["Fmaj9", "C/Bb", "Am7", "D7b9", "Gm7", "A7b13",
                                                     "Dm7", "Dbm7", "Cm7", "F13b9", "Bbmaj7", "A7b13",
                                                     "Dm7@2", "G13", "Gm7@2", "C7sus"] },
                { name: "Tema (variação)", repeat: 1, chords: ["Fmaj9", "C/Bb", "Am7", "D7b9", "Gm7", "A7b13",
                                                               "Dm7", "Db7", "Cm11", "F13b9", "Bbmaj7", "A7b13",
                                                               "Dm7@2", "G13", "Gm7@2", "C7sus", "Bb/C", "Gb/C"] },
                { name: "Parte B (em Lá♭)", repeat: 1, chords: ["Bbm7", "Eb7sus", "Eb7b9", "Abmaj7", "Fm7", "B13",
                                                                  "Bbm7", "Eb7sus", "Gm9", "C13b9"] },
                { name: "Tema", repeat: 1, chords: ["Fmaj9", "C/Bb", "Am7", "D7b9", "Gm7", "A7b13",
                                                     "Dm7", "Dbm7", "Cm7", "F13b9", "Bbmaj7", "A7b13",
                                                     "Dm7@2", "G13", "Gm7@2", "C7sus"] },
                { name: "Final", repeat: 1, strum: 1, chords: ["Dbmaj7", "Eb7sus@2", "Fmaj7"] }
            ]
        }
    ]
}
