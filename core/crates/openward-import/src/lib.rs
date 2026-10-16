//! Importers into the vault. They read another tool's configuration and
//! return vault items ready to create in one batch; they never write
//! anything themselves, and never touch the files they read.
//!
//! OpenSSH's client configuration ([`ssh_config`]) goes straight to vault
//! items. The other programs' importers ([`termius`], [`putty`] for PuTTY
//! and KiTTY, [`mobaxterm`], [`tabby`], [`securecrt`]) return a
//! [`bundle::Bundle`] that the app turns into items; [`detect`] says whose
//! a file is, and what is on this computer.

pub mod bundle;
pub mod detect;
pub mod mobaxterm;
pub mod putty;
pub mod securecrt;
pub mod ssh_config;
pub mod tabby;
pub mod termius;
mod text;
