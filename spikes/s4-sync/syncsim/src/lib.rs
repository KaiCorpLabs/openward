//! Spike S4, part 1: what the sync of v0.5 needs from the format that v0.4
//! writes. The v1 envelope (signed, encrypted, content-addressed), the
//! revision DAG, the hybrid logical clock and two ways to merge, run on
//! devices simulated in memory that share append-only logs.
//!
//! - [`envelope`]: the v1 envelope and its canonical CBOR.
//! - [`hlc`]: the hybrid logical clock.
//! - [`fields`]: an item's body as paths and values, for a merge that does
//!   not need to know the item's type.
//! - [`dag`]: an item's revisions, and the two merges: by field clocks, and
//!   three-way from the common ancestor (ADR-005 as written).
//! - [`sim`]: devices, their logs, compaction, and the oracle that says
//!   which writes must survive.
//! - [`bench`]: sizes, unlock time and the 10,000-edit runs.

pub mod bench;
pub mod cbor;
pub mod dag;
pub mod envelope;
pub mod fields;
pub mod hlc;
pub mod sim;
