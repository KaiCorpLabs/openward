//! libghostty-vt behind `openward_term::TermEngine`: the terminal engine of
//! OpenWard (ADR-002), with its input encoders (keys, mouse, paste, focus).
//!
//! The one crate allowed to use `unsafe`: generated bindings in [`sys`] and
//! the calls in `engine`. Everything it exposes is safe.

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
