//! Terminal state for OpenWard.
//!
//! The UI never talks to a terminal emulator directly. It receives damage
//! frames (see [`frame`]) produced by a [`TermEngine`], so the engine behind
//! it can change without touching Flutter code. The engine is libghostty-vt,
//! in `openward-ghostty` (ADR-002); `alacritty` stays behind a feature as a
//! second reference for the spikes.

pub mod engine;
pub mod frame;

#[cfg(feature = "alacritty")]
pub mod alacritty;

pub use engine::{CursorShape, CursorState, Size, TermEngine};
pub use frame::{Color, FrameEncoder, FrameStats, Style};
