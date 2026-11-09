//! Pontuação do jogo de batida: compara os toques do aluno com os tempos
//! em que a batida pede uma palhetada.

use serde::Serialize;

/// Até onde um toque ainda conta (em milissegundos, para cada lado).
pub const PERFECT_MS: f64 = 60.0;
pub const GOOD_MS: f64 = 130.0;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Judgement {
    /// Para cada palhetada esperada: 2 = perfeito, 1 = bom, 0 = perdeu.
    pub hits: Vec<u8>,
    /// Toques que não caíram perto de nenhuma palhetada.
    pub extra: usize,
    /// 0 a 100.
    pub score: u32,
}

/// `expected` e `taps` em milissegundos desde o começo, em ordem.
/// Cada toque só vale para uma palhetada (a mais próxima ainda livre).
pub fn judge(expected: &[f64], taps: &[f64]) -> Judgement {
    let mut hits = vec![0u8; expected.len()];
    let mut used = vec![false; expected.len()];
    let mut extra = 0;
    for &t in taps {
        let best = expected
            .iter()
            .enumerate()
            .filter(|(i, _)| !used[*i])
            .map(|(i, &e)| (i, (t - e).abs()))
            .filter(|&(_, d)| d <= GOOD_MS)
            .min_by(|a, b| a.1.total_cmp(&b.1));
        match best {
            Some((i, d)) => {
                used[i] = true;
                hits[i] = if d <= PERFECT_MS { 2 } else { 1 };
            }
            None => extra += 1,
        }
    }
    let points: u32 = hits.iter().map(|&h| h as u32).sum();
    let max = (expected.len() as u32 * 2).max(1);
    // Toque sobrando tira meio ponto, sem passar de zero.
    let score = (points as f64 - extra as f64 * 0.5).max(0.0) / max as f64 * 100.0;
    Judgement {
        hits,
        extra,
        score: score.round() as u32,
    }
}

/// Mesmo que [`judge`], recebendo e devolvendo JSON (para a interface).
pub fn judge_json(expected: &str, taps: &str) -> String {
    let e: Vec<f64> = serde_json::from_str(expected).unwrap_or_default();
    let t: Vec<f64> = serde_json::from_str(taps).unwrap_or_default();
    serde_json::to_string(&judge(&e, &t)).unwrap_or_else(|_| "{}".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn perfect_good_miss_and_extra() {
        let j = judge(
            &[0.0, 500.0, 1000.0, 1500.0],
            &[10.0, 600.0, 1250.0, 1490.0],
        );
        assert_eq!(j.hits, [2, 1, 0, 2]);
        assert_eq!(j.extra, 1);
        assert_eq!(j.score, 56); // (5 - 0.5) / 8
    }

    #[test]
    fn one_tap_counts_once() {
        let j = judge(&[0.0, 100.0], &[50.0]);
        assert_eq!(j.hits.iter().filter(|&&h| h > 0).count(), 1);
        assert_eq!(judge(&[], &[]).score, 0);
        assert!(judge_json("[0]", "[0]").contains("\"score\":100"));
    }
}
