//! Som do metrônomo: um "tic" curto gerado na hora, em WAV, para não
//! precisar guardar arquivos de áudio no app.

const RATE: u32 = 44_100;

/// WAV mono 16 bits, 44,1 kHz: seno na frequência pedida, caindo rápido.
pub fn click_wav(freq: f32, millis: u32) -> Vec<u8> {
    let n = RATE * millis / 1000;
    let samples: Vec<f32> = (0..n)
        .map(|i| {
            let t = i as f32 / RATE as f32;
            (2.0 * std::f32::consts::PI * freq * t).sin() * (-t * 60.0).exp() * 0.8
        })
        .collect();
    wav(&samples)
}

/// Som de batida do metrônomo: "batida" (bumbo e caixa, o forte é o bumbo),
/// "madeira" (bloco de madeira), "chimbal" ou "clique" (o tic de sempre).
pub fn beat_wav(kind: &str, accent: bool) -> Vec<u8> {
    use std::f32::consts::PI;
    let len = |ms: u32| (RATE * ms / 1000) as usize;
    // Ruído simples e repetível (sem depender de crate de números aleatórios).
    let mut seed: u32 = 0x1234_5678;
    let mut noise = move || {
        seed ^= seed << 13;
        seed ^= seed >> 17;
        seed ^= seed << 5;
        (seed as f32 / u32::MAX as f32) * 2.0 - 1.0
    };
    let samples: Vec<f32> = match kind {
        "batida" if accent => {
            // Bumbo: seno que cai de 150 Hz para 50 Hz, com um estalo no começo.
            let mut phase = 0.0f32;
            (0..len(260))
                .map(|i| {
                    let t = i as f32 / RATE as f32;
                    let f = 50.0 + 100.0 * (-t * 30.0).exp();
                    phase += 2.0 * PI * f / RATE as f32;
                    phase.sin() * (-t * 14.0).exp() * 0.95 + noise() * (-t * 300.0).exp() * 0.3
                })
                .collect()
        }
        "batida" => {
            // Caixa: ruído com um corpo em 190 Hz.
            (0..len(180))
                .map(|i| {
                    let t = i as f32 / RATE as f32;
                    noise() * (-t * 28.0).exp() * 0.6
                        + (2.0 * PI * 190.0 * t).sin() * (-t * 35.0).exp() * 0.4
                })
                .collect()
        }
        "madeira" => {
            let f = if accent { 1200.0 } else { 900.0 };
            (0..len(90))
                .map(|i| {
                    let t = i as f32 / RATE as f32;
                    let env = (-t * 70.0).exp();
                    ((2.0 * PI * f * t).sin() * 0.7 + (2.0 * PI * f * 2.7 * t).sin() * 0.25) * env
                })
                .collect()
        }
        "chimbal" => {
            let decay = if accent { 25.0 } else { 45.0 };
            let mut prev = 0.0f32;
            (0..len(120))
                .map(|i| {
                    let t = i as f32 / RATE as f32;
                    // Passa-altas simples para o ruído soar metálico.
                    let n = noise();
                    let hp = n - prev;
                    prev = n;
                    hp * (-t * decay).exp() * 0.5
                })
                .collect()
        }
        _ => return click_wav(if accent { 1760.0 } else { 1175.0 }, 60),
    };
    wav(&samples)
}

fn wav(samples: &[f32]) -> Vec<u8> {
    let mut data = Vec::with_capacity(samples.len() * 2);
    for s in samples {
        let v = (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
        data.extend_from_slice(&v.to_le_bytes());
    }
    let mut out = Vec::with_capacity(44 + data.len());
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes()); // tamanho do bloco fmt
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&1u16.to_le_bytes()); // mono
    out.extend_from_slice(&RATE.to_le_bytes());
    out.extend_from_slice(&(RATE * 2).to_le_bytes()); // bytes por segundo
    out.extend_from_slice(&2u16.to_le_bytes()); // bytes por amostra
    out.extend_from_slice(&16u16.to_le_bytes()); // bits
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(&data);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_a_valid_wav_header() {
        let w = click_wav(1000.0, 10);
        assert_eq!(&w[..4], b"RIFF");
        assert_eq!(&w[8..16], b"WAVEfmt ");
        assert_eq!(w.len(), 44 + 441 * 2);
        assert_eq!(u32::from_le_bytes(w[40..44].try_into().unwrap()), 882);
    }

    #[test]
    fn every_beat_sound_is_a_wav() {
        for kind in ["batida", "madeira", "chimbal", "clique"] {
            for accent in [true, false] {
                let w = beat_wav(kind, accent);
                assert_eq!(&w[..4], b"RIFF", "{kind}");
                assert!(w.len() > 1000, "{kind}");
            }
        }
    }
}
