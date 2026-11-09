//! Núcleo do AraraCypher: tudo que não depende de interface.
//!
//! Este crate é Rust puro, para poder ser testado com `cargo test`
//! sem precisar do Qt instalado.

pub mod chord;
pub mod chorddb;
pub mod library;
pub mod matching;
pub mod lyrics;
pub mod ocr;
pub mod pitch;
pub mod rhythm;
pub mod shape;
pub mod sheet;
pub mod song;
pub mod sound;
pub mod tab;
pub mod web;

pub use chord::{Accidental, Chord, Note, ParseChordError};
pub use shape::{shape_for, ChordShape};
