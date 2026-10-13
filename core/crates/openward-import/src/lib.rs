//! Importers into the vault. They read another tool's configuration and
//! return vault items ready to create in one batch; they never write
//! anything themselves, and never touch the files they read.
//!
//! For now there is OpenSSH's client configuration ([`ssh_config`]). PuTTY,
//! MobaXterm and Termius come later in phase 1.

pub mod ssh_config;
