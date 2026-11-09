//! Escuta pelo microfone: a nota que está soando (afinador) e quanto de cada
//! uma das 12 notas há no som (para reconhecer o acorde tocado).

/// Volume (raiz da média dos quadrados) do trecho.
pub fn rms(x: &[f32]) -> f32 {
    if x.is_empty() {
        return 0.0;
    }
    (x.iter().map(|v| v * v).sum::<f32>() / x.len() as f32).sqrt()
}

/// Frequência fundamental pelo método YIN, entre 60 Hz e 1200 Hz (cobre o
/// violão inteiro). `None` se o som está baixo demais ou não tem nota clara.
pub fn detect(x: &[f32], rate: u32) -> Option<f32> {
    if x.len() < 512 || rms(x) < 0.005 {
        return None;
    }
    let rate = rate as f32;
    let w = x.len() / 2;
    let min_tau = (rate / 1200.0).floor().max(2.0) as usize;
    let max_tau = ((rate / 60.0).ceil() as usize).min(w - 1);
    if max_tau <= min_tau + 2 {
        return None;
    }
    // Diferença e diferença normalizada acumulada.
    let mut d = vec![0.0f32; max_tau + 2];
    for (tau, dv) in d.iter_mut().enumerate().take(max_tau + 2).skip(1) {
        let mut s = 0.0f32;
        for i in 0..w {
            let v = x[i] - x[i + tau];
            s += v * v;
        }
        *dv = s;
    }
    let mut cmnd = vec![1.0f32; max_tau + 2];
    let mut sum = 0.0f32;
    for tau in 1..max_tau + 2 {
        sum += d[tau];
        cmnd[tau] = if sum > 0.0 {
            d[tau] * tau as f32 / sum
        } else {
            1.0
        };
    }
    const THRESHOLD: f32 = 0.15;
    let mut tau = min_tau;
    let mut found = None;
    while tau <= max_tau {
        if cmnd[tau] < THRESHOLD {
            while tau < max_tau && cmnd[tau + 1] < cmnd[tau] {
                tau += 1;
            }
            found = Some(tau);
            break;
        }
        tau += 1;
    }
    // Sem passar do limite: o menor valor, se for razoavelmente claro.
    let tau = match found {
        Some(t) => t,
        None => {
            let (t, v) = (min_tau..=max_tau)
                .map(|t| (t, cmnd[t]))
                .fold((0, f32::MAX), |a, b| if b.1 < a.1 { b } else { a });
            if v > 0.35 {
                return None;
            }
            t
        }
    };
    // Interpolação parabólica para não ficar preso ao inteiro.
    let (a, b, c) = (cmnd[tau - 1], cmnd[tau], cmnd[tau + 1]);
    let den = a - 2.0 * b + c;
    let shift = if den.abs() > 1e-9 {
        0.5 * (a - c) / den
    } else {
        0.0
    };
    Some(rate / (tau as f32 + shift.clamp(-1.0, 1.0)))
}

/// Força de cada nota (Dó = 0 ... Si = 11) do Mi grave (E2) ao Mi da 24ª casa
/// (E6), somando as oitavas. Normalizado para o maior valor ser 1.
pub fn chroma(x: &[f32], rate: u32) -> [f32; 12] {
    let mut out = [0.0f32; 12];
    if x.len() < 512 || rms(x) < 0.005 {
        return out;
    }
    let n = x.len();
    // Janela de Hann, para cada nota não vazar nas vizinhas.
    let win: Vec<f32> = (0..n)
        .map(|i| {
            let t = std::f32::consts::PI * 2.0 * i as f32 / (n - 1) as f32;
            x[i] * (0.5 - 0.5 * t.cos())
        })
        .collect();
    for midi in 40..=88 {
        let f = 440.0 * 2f32.powf((midi as f32 - 69.0) / 12.0);
        // Goertzel na frequência da nota.
        let k = 2.0 * (std::f32::consts::PI * 2.0 * f / rate as f32).cos();
        let (mut s1, mut s2) = (0.0f32, 0.0f32);
        for &v in &win {
            let s0 = v + k * s1 - s2;
            s2 = s1;
            s1 = s0;
        }
        let power = s1 * s1 + s2 * s2 - k * s1 * s2;
        out[midi % 12] += power.max(0.0).sqrt();
    }
    let max = out.iter().cloned().fold(0.0, f32::max);
    if max > 0.0 {
        for v in out.iter_mut() {
            *v /= max;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(freqs: &[f32], rate: u32, n: usize) -> Vec<f32> {
        (0..n)
            .map(|i| {
                let t = i as f32 / rate as f32;
                freqs
                    .iter()
                    .map(|f| {
                        // Com harmônicos, como uma corda de verdade.
                        (2.0 * std::f32::consts::PI * f * t).sin() * 0.3
                            + (4.0 * std::f32::consts::PI * f * t).sin() * 0.15
                            + (6.0 * std::f32::consts::PI * f * t).sin() * 0.08
                    })
                    .sum()
            })
            .collect()
    }

    #[test]
    fn finds_open_strings() {
        for f in [82.41f32, 110.0, 146.83, 196.0, 246.94, 329.63] {
            let got = detect(&tone(&[f], 44100, 4096), 44100).unwrap();
            assert!((got - f).abs() / f < 0.005, "{f} -> {got}");
        }
    }

    #[test]
    fn silence_has_no_note() {
        assert!(detect(&vec![0.0; 4096], 44100).is_none());
    }

    #[test]
    fn chroma_of_e_minor() {
        // E2 B2 E3 G3 B3 E4.
        let c = chroma(
            &tone(&[82.41, 123.47, 164.81, 196.0, 246.94, 329.63], 44100, 8192),
            44100,
        );
        let mut best: Vec<usize> = (0..12).collect();
        best.sort_by(|a, b| c[*b].partial_cmp(&c[*a]).unwrap());
        let top: Vec<usize> = best[..3].to_vec();
        for pc in [4usize, 7, 11] {
            assert!(top.contains(&pc), "{top:?} {c:?}");
        }
    }
}
