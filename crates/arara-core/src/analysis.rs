//! Audio analysis for transitions between tracks (crossfade, "smart" mix).
//!
//! Ideas borrowed from open-source players:
//! - silence trimming (Audacious crossfade, Mixxx Auto DJ "Skip Silence"):
//!   where the music really starts and ends;
//! - MixRamp (MPD): how long the track takes to get loud at the start and
//!   where it fades out at the end, so two songs overlap only in their quiet
//!   parts and the overlap is as long as the songs themselves allow;
//! - loudness (EBU R128, like ReplayGain 2 / rsgain) for tracks without tags;
//! - tempo and first beat (Mixxx-style beat grid, much simpler), so a
//!   transition can start on a beat of the outgoing song and the incoming
//!   one can enter on its own first beat.
//!
//! One pass over the decoded audio, mono at the file's sample rate. Results
//! are cached in the `track_analysis` table, keyed by the file's mtime.

use std::fs::File;
use std::path::Path;

use serde::{Deserialize, Serialize};
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Bump when the algorithm changes, so old cached results are recomputed.
pub const VERSION: i64 = 1;

/// Envelope resolution: one block = 10 ms.
const BLOCK_MS: usize = 10;
/// Below this a block counts as silence (dBFS RMS).
const SILENCE_DB: f32 = -55.0;
/// "Quiet part" threshold, relative to the track's typical loudness (MixRamp-like).
const RAMP_REL_DB: f32 = -9.0;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Analysis {
    pub duration_ms: i64,
    /// First non-silent moment.
    pub intro_ms: i64,
    /// End of the last non-silent moment.
    pub outro_ms: i64,
    /// When the track first reaches its normal level (end of a fade-in).
    pub ramp_in_ms: i64,
    /// When the track drops below its normal level for good (start of its fade-out).
    pub ramp_out_ms: i64,
    /// Integrated loudness (LUFS), None for silence.
    pub lufs: Option<f64>,
    /// Estimated tempo; None when the beat is not clear enough.
    pub bpm: Option<f64>,
    /// Time of the first beat at or after `intro_ms`.
    pub beat_ms: Option<f64>,
}

#[derive(Debug, thiserror::Error)]
pub enum AnalysisError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("decode: {0}")]
    Decode(String),
}

impl From<SymError> for AnalysisError {
    fn from(e: SymError) -> Self {
        AnalysisError::Decode(e.to_string())
    }
}

/// Decode `path` and analyse it. Takes ~0.1–0.3 s per song in release builds.
pub fn analyze_file(path: &Path) -> Result<Analysis, AnalysisError> {
    let file = File::open(path)?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let probed = symphonia::default::get_probe().format(
        &hint,
        mss,
        &FormatOptions { enable_gapless: true, ..Default::default() },
        &MetadataOptions::default(),
    )?;
    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or_else(|| AnalysisError::Decode("no audio track".into()))?;
    let track_id = track.id;
    let mut decoder = symphonia::default::get_codecs().make(&track.codec_params, &DecoderOptions::default())?;

    let mut acc: Option<Accumulator> = None;
    let mut buf: Option<SampleBuffer<f32>> = None;
    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(SymError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(SymError::ResetRequired) => break,
            Err(e) => return Err(e.into()),
        };
        if packet.track_id() != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(SymError::DecodeError(_)) => continue, // skip a corrupt frame, like players do
            Err(e) => return Err(e.into()),
        };
        let spec = *decoded.spec();
        if buf.as_ref().map(|b| b.capacity() < decoded.capacity() * spec.channels.count()).unwrap_or(true) {
            buf = Some(SampleBuffer::new(decoded.capacity() as u64, spec));
        }
        let b = buf.as_mut().unwrap();
        b.copy_interleaved_ref(decoded);
        let a = acc.get_or_insert_with(|| Accumulator::new(spec.rate, spec.channels.count()));
        a.push(b.samples());
    }
    let acc = acc.ok_or_else(|| AnalysisError::Decode("no audio".into()))?;
    Ok(acc.finish())
}

/// Builds the 10 ms energy envelope and the loudness meter while decoding.
struct Accumulator {
    rate: u32,
    channels: usize,
    block_len: usize,
    cur_sum: f64,
    cur_n: usize,
    blocks: Vec<f32>, // mean square per block (mono)
    meter: Option<ebur128::EbuR128>,
    frames: u64,
}

impl Accumulator {
    fn new(rate: u32, channels: usize) -> Self {
        let mch = channels.min(2) as u32;
        Accumulator {
            rate,
            channels,
            block_len: (rate as usize * BLOCK_MS / 1000).max(1),
            cur_sum: 0.0,
            cur_n: 0,
            blocks: Vec::with_capacity(60_000),
            meter: ebur128::EbuR128::new(mch.max(1), rate, ebur128::Mode::I).ok(),
            frames: 0,
        }
    }

    fn push(&mut self, interleaved: &[f32]) {
        let ch = self.channels.max(1);
        if let Some(m) = self.meter.as_mut() {
            if ch <= 2 {
                let _ = m.add_frames_f32(interleaved);
            } else {
                let stereo: Vec<f32> = interleaved.chunks(ch).flat_map(|f| [f[0], f[1]]).collect();
                let _ = m.add_frames_f32(&stereo);
            }
        }
        for frame in interleaved.chunks(ch) {
            let s: f32 = frame.iter().sum::<f32>() / ch as f32;
            self.cur_sum += (s * s) as f64;
            self.cur_n += 1;
            if self.cur_n == self.block_len {
                self.blocks.push((self.cur_sum / self.cur_n as f64) as f32);
                self.cur_sum = 0.0;
                self.cur_n = 0;
            }
        }
        self.frames += (interleaved.len() / ch) as u64;
    }

    fn finish(mut self) -> Analysis {
        if self.cur_n > 0 {
            self.blocks.push((self.cur_sum / self.cur_n as f64) as f32);
        }
        let duration_ms = (self.frames as f64 * 1000.0 / self.rate as f64).round() as i64;
        let lufs = self.meter.as_ref().and_then(|m| m.loudness_global().ok()).filter(|l| l.is_finite());
        envelope_analysis(&self.blocks, duration_ms, lufs)
    }
}

fn db(ms: f32) -> f32 {
    10.0 * (ms.max(1e-12)).log10()
}

/// Everything but decoding, so it can be tested with synthetic envelopes.
pub fn envelope_analysis(blocks: &[f32], duration_ms: i64, lufs: Option<f64>) -> Analysis {
    let n = blocks.len();
    let bms = BLOCK_MS as i64;
    let mut a = Analysis { duration_ms, intro_ms: 0, outro_ms: duration_ms, ramp_in_ms: 0, ramp_out_ms: duration_ms, lufs, bpm: None, beat_ms: None };
    if n == 0 {
        return a;
    }
    let dbs: Vec<f32> = blocks.iter().map(|&b| db(b)).collect();
    let first = dbs.iter().position(|&d| d > SILENCE_DB);
    let last = dbs.iter().rposition(|&d| d > SILENCE_DB);
    let (Some(first), Some(last)) = (first, last) else {
        return a; // all silence
    };
    a.intro_ms = first as i64 * bms;
    a.outro_ms = ((last as i64 + 1) * bms).min(duration_ms);

    // Smoothed level (300 ms moving average of energy) for the ramps.
    let w = 30usize;
    let mut smooth = vec![0f32; n];
    let mut sum = 0f64;
    for i in 0..n {
        sum += blocks[i] as f64;
        if i >= w {
            sum -= blocks[i - w] as f64;
        }
        smooth[i] = db((sum / (i.min(w - 1) + 1) as f64) as f32);
    }
    // "Normal level": median of the non-silent smoothed blocks.
    let mut loud: Vec<f32> = smooth[first..=last].iter().copied().filter(|&d| d > SILENCE_DB).collect();
    if !loud.is_empty() {
        loud.sort_by(|x, y| x.partial_cmp(y).unwrap());
        let typical = loud[loud.len() / 2];
        let thr = typical + RAMP_REL_DB;
        // Smoothing delays the curve by ~w/2 blocks; compensate.
        if let Some(i) = smooth[first..=last].iter().position(|&d| d >= thr) {
            a.ramp_in_ms = ((first + i).saturating_sub(w / 2) as i64 * bms).max(a.intro_ms);
        }
        if let Some(i) = smooth[first..=last].iter().rposition(|&d| d >= thr) {
            a.ramp_out_ms = ((first + i) as i64 * bms).min(a.outro_ms);
        }
    }
    a.ramp_in_ms = a.ramp_in_ms.clamp(a.intro_ms, a.outro_ms);
    a.ramp_out_ms = a.ramp_out_ms.clamp(a.ramp_in_ms, a.outro_ms);

    if let Some((bpm, phase_ms)) = estimate_tempo(&dbs, first, (a.ramp_in_ms / bms) as usize, (a.ramp_out_ms / bms) as usize) {
        a.bpm = Some((bpm * 10.0).round() / 10.0);
        a.beat_ms = Some(phase_ms);
    }
    a
}

/// Tempo from the autocorrelation of an onset curve (rises in energy), the
/// classic approach used by simple beat trackers. Returns (bpm, first beat ms).
fn estimate_tempo(dbs: &[f32], first: usize, body_from: usize, body_to: usize) -> Option<(f64, f64)> {
    let n = dbs.len();
    let body_to = body_to.min(n);
    if body_to < body_from + 1500 || n < 1500 {
        return None; // < 15 s
    }
    // Onset strength: positive difference of the log energy, lightly smoothed.
    let mut onset = vec![0f32; n];
    for i in 1..n {
        // (ignore sub-dB wobble: steady tones ripple a little between blocks)
        onset[i] = (dbs[i] - dbs[i - 1] - 0.5).max(0.0).min(30.0);
    }
    // Remove the local mean so sustained loudness doesn't count.
    let w = 50;
    let mut out = vec![0f32; n];
    let mut s = 0f32;
    for i in 0..n {
        s += onset[i];
        if i >= w {
            s -= onset[i - w];
        }
        out[i] = (onset[i] - s / (i.min(w - 1) + 1) as f32).max(0.0);
    }
    // Analyse up to 90 s from the middle of the song.
    // (only the body of the song: fades and silence have no beat)
    let body = body_to - body_from;
    let len = body.min(9000);
    let start = body_from + (body - len) / 2;
    let seg = &out[start..start + len];
    // A steady tone or near silence has no onsets worth tracking.
    let strength: f64 = seg.iter().map(|&x| x as f64).sum::<f64>() / len as f64;
    log::debug!("onset strength {strength:.4}");
    if strength < 0.05 {
        return None;
    }
    // Lags for 70–180 BPM at 100 blocks/s.
    let (min_lag, max_lag) = (100 * 60 / 180, 100 * 60 / 70);
    let mut best = (0usize, 0f64);
    let mut scores = vec![0f64; max_lag + 2];
    for lag in min_lag..=max_lag + 1 {
        let mut acc = 0f64;
        for i in 0..len - lag {
            acc += (seg[i] * seg[i + lag]) as f64;
        }
        scores[lag] = acc / (len - lag) as f64;
    }
    for lag in min_lag..=max_lag {
        // Favour the beat over its double/half a little (like a tempo prior around 120).
        let bpm = 6000.0 / lag as f64;
        let prior = (-((bpm / 120.0).log2()).powi(2) / 0.5).exp();
        let sc = scores[lag] * (0.6 + 0.4 * prior);
        if sc > best.1 {
            best = (lag, sc);
        }
    }
    let mean: f64 = scores[min_lag..=max_lag].iter().sum::<f64>() / (max_lag - min_lag + 1) as f64;
    if best.0 == 0 || mean <= 0.0 || best.1 < mean * 1.35 {
        return None; // no clear pulse (ambient, classical, speech)
    }
    // Sub-block precision with a parabola through the neighbours.
    let l = best.0;
    let (y0, y1, y2) = (scores[l - 1], scores[l], scores[l + 1]);
    let denom = y0 - 2.0 * y1 + y2;
    let frac = if denom.abs() > 1e-12 { 0.5 * (y0 - y2) / denom } else { 0.0 };
    let period = l as f64 + frac.clamp(-0.5, 0.5);
    let bpm = 6000.0 / period;

    // Phase: offset that collects the most onset energy on the grid.
    let p = period;
    let mut best_phase = (0f64, -1f64);
    let steps = l.max(1);
    for k in 0..steps {
        let off = k as f64;
        let mut acc = 0f64;
        let mut t = start as f64 + off;
        while (t as usize) < start + len {
            acc += out[t as usize] as f64;
            t += p;
        }
        if acc > best_phase.1 {
            best_phase = (off, acc);
        }
    }
    // Project the grid back to the first beat at or after the music starts.
    let phase_abs = start as f64 + best_phase.0;
    let k = ((phase_abs - first as f64) / p).floor();
    let mut first_beat = phase_abs - k * p;
    while first_beat < first as f64 {
        first_beat += p;
    }
    Some((bpm, first_beat * BLOCK_MS as f64))
}

/// Cached analysis for a track, recomputed when the file changes.
pub fn cached_or_analyze(db: &crate::db::Db, track_id: i64) -> Option<Analysis> {
    let (path, mtime): (String, i64) = db
        .conn
        .query_row("SELECT path, mtime FROM tracks WHERE id=?1", [track_id], |r| Ok((r.get(0)?, r.get(1)?)))
        .ok()?;
    if path.starts_with(crate::remote::PREFIX) {
        return None; // would mean downloading the whole song
    }
    let cached: Option<(i64, i64, String)> = db
        .conn
        .query_row("SELECT version, mtime, json FROM track_analysis WHERE track_id=?1", [track_id], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })
        .ok();
    if let Some((v, m, json)) = cached {
        if v == VERSION && m == mtime {
            if let Ok(a) = serde_json::from_str(&json) {
                return Some(a);
            }
        }
    }
    let a = analyze_file(Path::new(&path)).map_err(|e| log::warn!("analysis of {path}: {e}")).ok()?;
    let _ = db.conn.execute(
        "INSERT OR REPLACE INTO track_analysis(track_id, version, mtime, json) VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params![track_id, VERSION, mtime, serde_json::to_string(&a).unwrap_or_default()],
    );
    Some(a)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone_blocks(secs: f32, silence_head: f32, silence_tail: f32, fade_out: f32) -> Vec<f32> {
        let n = ((silence_head + secs + silence_tail) * 100.0) as usize;
        let h = (silence_head * 100.0) as usize;
        let e = h + (secs * 100.0) as usize;
        let f = e - (fade_out * 100.0) as usize;
        (0..n)
            .map(|i| {
                if i < h || i >= e {
                    0.0
                } else {
                    let base = 0.05f32 * if (i / 25) % 2 == 0 { 1.0 } else { 0.3 }; // 2 "beats"/s = 120 BPM
                    if i >= f {
                        let k = (e - i) as f32 / (e - f) as f32;
                        base * k.powi(4)
                    } else {
                        base
                    }
                }
            })
            .collect()
    }

    #[test]
    fn trims_silence_and_finds_fade_out() {
        let b = tone_blocks(60.0, 2.0, 3.0, 8.0);
        let a = envelope_analysis(&b, 65_000, Some(-14.0));
        assert!((a.intro_ms - 2000).abs() <= 20, "intro {}", a.intro_ms);
        assert!(a.outro_ms > 60_000 && a.outro_ms <= 62_000, "outro {}", a.outro_ms);
        assert!(a.ramp_out_ms < 61_000 && a.ramp_out_ms > 54_000, "ramp out {}", a.ramp_out_ms);
        assert!(a.ramp_in_ms <= 2400, "ramp in {}", a.ramp_in_ms);
    }

    #[test]
    fn finds_tempo() {
        let b = tone_blocks(60.0, 1.0, 0.0, 0.0);
        let a = envelope_analysis(&b, 61_000, None);
        let bpm = a.bpm.expect("tempo");
        assert!((bpm - 120.0).abs() < 2.0, "bpm {bpm}");
        let beat = a.beat_ms.unwrap();
        assert!(beat >= 1000.0 && beat < 1600.0, "beat {beat}");
    }

    #[test]
    fn silence_only() {
        let a = envelope_analysis(&vec![0.0; 500], 5000, None);
        assert_eq!((a.intro_ms, a.outro_ms), (0, 5000));
    }
}
