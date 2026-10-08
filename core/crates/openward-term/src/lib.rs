//! Terminal state for OpenWard.
//!
//! The UI never talks to a terminal emulator directly. It receives damage
//! frames (see [`frame`]) produced by a [`TermEngine`], so the engine behind
//! it can change without touching Flutter code. Spike S1 compares the
//! candidate engines through this same interface (ADR-002).

pub mod engine;
pub mod frame;

#[cfg(feature = "alacritty")]
pub mod alacritty;

pub use engine::{CursorShape, CursorState, Size, TermEngine};
pub use frame::{Color, FrameEncoder, FrameStats, Style};
