//! libghostty-vt behind `openward_term::TermEngine` (spike S1.3, candidate B).
//!
//! All `unsafe` lives in this crate: generated bindings in [`sys`] and the
//! calls in [`engine`] and its input encoders. Nothing here is promoted to `core/` unless the spike
//! picks this engine (ADR-002).

#[allow(
    non_upper_case_globals,
    non_camel_case_types,
    non_snake_case,
    dead_code,
    unsafe_op_in_unsafe_fn,
    clippy::all
)]
#[rustfmt::skip]
pub mod sys;

mod engine;

pub use engine::input::{
    InputModes, KeyAction, KeyInput, MouseAction, MouseButton, MouseInput, Paste, mods,
};
pub use engine::{CompressionReport, GhosttyEngine};
