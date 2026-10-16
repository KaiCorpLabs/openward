//! Describes the shape of the Termius data on this computer, to check that
//! OpenWard understands its format, without any of its values: database
//! and field names, how many records, and what kind of value each field
//! holds. It only reads.
//!
//!   cargo run -p openward-import --example termius_probe [--decrypt] [data folder]
//!
//! With `--decrypt` it also asks the keychain for Termius's key (the
//! system asks you first) and shows what the encrypted fields hold: field
//! names and kinds, still no values.

use std::path::PathBuf;

use openward_import::termius;

fn main() {
    let home = std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .expect("HOME");
    let mut args: Vec<_> = std::env::args_os().skip(1).collect();
    let decrypt = args.iter().any(|a| a == "--decrypt");
    args.retain(|a| a != "--decrypt");
    let keys = if decrypt {
        match termius::keychain::local_keys() {
            Ok(k) if !k.is_empty() => k,
            Ok(_) => {
                eprintln!("Termius's key is not in the keychain");
                std::process::exit(1);
            }
            Err(e) => {
                eprintln!("Could not read Termius's key: {e}");
                std::process::exit(1);
            }
        }
    } else {
        Vec::new()
    };
    let data = match args.into_iter().next() {
        Some(dir) => PathBuf::from(dir),
        None => match termius::find(&home) {
            Some(d) => d,
            None => {
                eprintln!("No Termius data found in:");
                for d in termius::data_dirs(&home) {
                    eprintln!("  {}", d.display());
                }
                std::process::exit(1);
            }
        },
    };
    let Some(leveldb) = termius::leveldb_dir(&data) else {
        eprintln!(
            "{} has no IndexedDB/file__0.indexeddb.leveldb",
            data.display()
        );
        if let Ok(entries) = std::fs::read_dir(data.join("IndexedDB")) {
            eprintln!("IndexedDB holds:");
            for e in entries.flatten() {
                eprintln!("  {}", e.file_name().to_string_lossy());
            }
        }
        std::process::exit(1);
    };
    let shape = match termius::shape(&leveldb, &keys) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Could not read it: {e}");
            std::process::exit(1);
        }
    };
    println!("Termius data in {}", data.display());
    println!("{} tables and {} logs read", shape.tables, shape.logs);
    for (why, n) in &shape.unreadable {
        println!("{n} records unreadable: {why}");
    }
    for (db, stores) in &shape.databases {
        for (store, s) in stores {
            println!("\n{db} / {store}: {} records", s.records);
            for (field, kinds) in &s.fields {
                let kinds: Vec<String> = kinds.iter().map(|(k, n)| format!("{k:?} ×{n}")).collect();
                let inner = s
                    .nested
                    .get(field)
                    .map(|f| format!(" {{{}}}", f.iter().cloned().collect::<Vec<_>>().join(", ")))
                    .unwrap_or_default();
                println!("  {field}: {}{inner}", kinds.join(", "));
                if let Some(inside) = s.decrypted.get(field) {
                    let inside: Vec<String> = inside
                        .iter()
                        .map(|(k, kinds)| {
                            if kinds.is_empty() {
                                k.clone()
                            } else {
                                format!(
                                    "{k}: {}",
                                    kinds.iter().copied().collect::<Vec<_>>().join("/")
                                )
                            }
                        })
                        .collect();
                    println!("    decrypted: {}", inside.join(", "));
                }
            }
            if s.undecryptable > 0 {
                println!("  ({} encrypted fields did not decrypt)", s.undecryptable);
            }
        }
    }
}
