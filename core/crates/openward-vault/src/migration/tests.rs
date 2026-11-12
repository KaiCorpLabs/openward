use super::*;
use crate::Vault;
use openward_proto::{Body, Data, Host, Item};

const PASSWORD: &[u8] = b"public test master password";
const MARKER: &str = "D3-private-host-72b64e8c.example";
fn params() -> KdfParams {
    KdfParams::new(64 * 1024, 1).unwrap()
}
fn item(id: ItemId, marker: &str) -> Item {
    Item {
        id,
        rev: 1,
        body: Body {
            created: 1,
            modified: 2,
            data: Data::Host(Host {
                label: marker.into(),
                address: marker.into(),
                ..Host::default()
            }),
        },
    }
}
fn legacy(path: &Path) -> ItemId {
    let mut s = Store::open(path).unwrap();
    let id = ItemId::new();
    s.write(&[item(id, MARKER)], &[]).unwrap();
    id
}
fn no_marker(dir: &Path) {
    for e in std::fs::read_dir(dir).unwrap() {
        let p = e.unwrap().path();
        if p.is_file() {
            let bytes = std::fs::read(&p).unwrap();
            assert!(
                !bytes.windows(MARKER.len()).any(|w| w == MARKER.as_bytes()),
                "plaintext in {}",
                p.display()
            );
        }
    }
}

#[test]
fn migration_encrypts_deleted_pages_wal_metadata_and_reopens_for_writes() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let id = legacy(&path);
    // Force old deleted content into freelist. Extension metadata must not
    // remain as plaintext; the subprocess test below leaves a real hot WAL.
    let mut raw = store::connect(&path, false).unwrap();
    raw.pragma_update(None, "secure_delete", "OFF").unwrap();
    raw.pragma_update(None, "wal_autocheckpoint", 0).unwrap();
    let old = ItemId::new();
    let vault = store::id(&raw, "vault_id").unwrap();
    raw.execute(
        "INSERT INTO items VALUES (?1,?2,1,?3)",
        params![
            vault.as_bytes().as_slice(),
            old.as_bytes().as_slice(),
            vec![MARKER.as_bytes(); 1000].concat()
        ],
    )
    .unwrap();
    raw.execute(
        "DELETE FROM items WHERE item_id=?1",
        [old.as_bytes().as_slice()],
    )
    .unwrap();
    raw.execute(
        "INSERT INTO meta VALUES ('future-setting',?1)",
        [MARKER.as_bytes()],
    )
    .unwrap();
    let tx = raw.transaction().unwrap();
    tx.execute(
        "UPDATE items SET head_rev=3 WHERE item_id=?1",
        [id.as_bytes().as_slice()],
    )
    .unwrap();
    tx.commit().unwrap();
    // Close before install; a subprocess crash test below covers a hot WAL.
    drop(raw);
    let locked = Vault::migrate_encrypted(&path, PASSWORD, params()).unwrap();
    assert!(matches!(Vault::open(&path), Err(Error::OpenElsewhere)));
    // Windows locks are mandatory: even a read of the empty .lock file is
    // refused while held. Close it before scanning every sibling, then reopen.
    drop(locked);
    no_marker(dir.path());
    let locked = Vault::open_locked(&path).unwrap();
    let mut v = locked.unlock(PASSWORD).unwrap();
    assert!(v.is_encrypted());
    assert_eq!(v.item(id).unwrap().rev, 3);
    assert_eq!(v.host(id).unwrap().address, MARKER);
    assert_eq!(
        v.metadata_value("future-setting")
            .unwrap()
            .unwrap()
            .as_slice(),
        MARKER.as_bytes()
    );
    let mut body = v.item(id).unwrap().body.clone();
    if let Data::Host(h) = &mut body.data {
        h.label = "renamed".into();
    }
    v.update(id, 3, body.data).unwrap();
    let locked = v.lock().unwrap();
    assert!(locked.store.keys.is_none());
    let v = locked.unlock(PASSWORD).unwrap();
    assert_eq!(v.host(id).unwrap().label, "renamed");
    drop(v);
    no_marker(dir.path());
    assert!(matches!(Vault::open(&path), Err(Error::Locked)));
    assert!(Vault::open_encrypted(&path, b"wrong password").is_err());
    assert!(Vault::open_encrypted(&path, PASSWORD).is_ok());
}

#[test]
fn pre_install_failures_keep_original_and_post_install_errors_report_commit() {
    for fail in [
        Phase::Staged,
        Phase::Verified,
        Phase::BeforeInstall,
        Phase::Installed,
    ] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let id = legacy(&path);
        let result = install(&path, PASSWORD, params(), true, |p| {
            if p == fail {
                Err(Error::Invalid("injected storage failure"))
            } else {
                Ok(())
            }
        });
        if fail == Phase::Installed {
            assert!(matches!(result, Err(Error::MigrationInstalled(_))));
            no_marker(dir.path());
            assert_eq!(
                Vault::open_encrypted(&path, PASSWORD)
                    .unwrap()
                    .host(id)
                    .unwrap()
                    .address,
                MARKER
            );
        } else {
            assert!(
                matches!(result, Err(Error::Invalid(_))),
                "{fail:?}: {:?}",
                result.err()
            );
            assert_eq!(
                Vault::open(&path).unwrap().host(id).unwrap().address,
                MARKER
            );
            assert!(!std::fs::read_dir(dir.path()).unwrap().any(|e| {
                e.unwrap()
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".openward-encrypted-")
            }));
        }
    }
}

#[test]
fn malformed_foreign_future_and_trailing_rows_abort_without_normalizing() {
    for case in 0..8 {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let id = legacy(&path);
        let conn = store::connect(&path, false).unwrap();
        match case {
            0 => {
                conn.execute("UPDATE items SET item_id=?1", [vec![1u8; 3]])
                    .unwrap();
            }
            1 => {
                conn.execute("UPDATE items SET vault_id=?1", [vec![1u8; 16]])
                    .unwrap();
            }
            2 => {
                conn.execute("UPDATE items SET head_rev=-1", []).unwrap();
            }
            3 => {
                let b: Vec<u8> = conn
                    .query_row("SELECT envelope FROM items", [], |r| r.get(0))
                    .unwrap();
                let mut b = b;
                b.push(0);
                conn.execute("UPDATE items SET envelope=?1", [b]).unwrap();
            }
            4 => {
                conn.execute(
                    "UPDATE items SET envelope=?1",
                    [vec![
                        0xa2, 0x61, b'v', 2, 0x64, b'b', b'o', b'd', b'y', 0x40,
                    ]],
                )
                .unwrap();
            }
            5 => {
                conn.execute_batch("CREATE TABLE future (private BLOB)")
                    .unwrap();
            }
            6 => {
                conn.execute_batch("CREATE TABLE sqlitex_private (note BLOB); INSERT INTO sqlitex_private VALUES (x'010203')").unwrap();
            }
            _ => {
                conn.execute_batch(
                    "ALTER TABLE meta ADD COLUMN future BLOB GENERATED ALWAYS AS (value) VIRTUAL",
                )
                .unwrap();
            }
        }
        let before: Vec<u8> = conn
            .query_row("SELECT envelope FROM items", [], |r| r.get(0))
            .unwrap();
        drop(conn);
        assert!(
            Vault::migrate_encrypted(&path, PASSWORD, params()).is_err(),
            "case {case}"
        );
        let conn = store::connect(&path, false).unwrap();
        assert_eq!(
            conn.pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
        assert_eq!(
            conn.query_row("SELECT envelope FROM items", [], |r| r.get::<_, Vec<u8>>(0))
                .unwrap(),
            before
        );
        let _ = id;
    }
}

#[test]
fn unknown_body_is_preserved_as_opaque_ciphertext_and_metadata_names_cannot_collide() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    legacy(&path);
    let conn = store::connect(&path, false).unwrap();
    let vault = store::id(&conn, "vault_id").unwrap();
    let id = ItemId::new();
    let unknown = vec![
        0xa1, 0x64, b't', b'y', b'p', b'e', 0x66, b'f', b'u', b't', b'u', b'r', b'e',
    ];
    let mut raw = vec![
        0xa2,
        0x61,
        b'v',
        0,
        0x64,
        b'b',
        b'o',
        b'd',
        b'y',
        0x40 + unknown.len() as u8,
    ];
    raw.extend(&unknown);
    conn.execute(
        "INSERT INTO items VALUES (?1,?2,42,?3)",
        params![vault.as_bytes().as_slice(), id.as_bytes().as_slice(), raw],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO meta VALUES (?1,?2)",
        params![CRYPTO, MARKER.as_bytes()],
    )
    .unwrap();
    drop(conn);
    let v = Vault::migrate_encrypted(&path, PASSWORD, params())
        .unwrap()
        .unlock(PASSWORD)
        .unwrap();
    assert_eq!(v.unreadable(), 1);
    assert_eq!(
        v.metadata_value(CRYPTO).unwrap().unwrap().as_slice(),
        MARKER.as_bytes()
    );
    let (_, _, bytes) = v
        .store
        .rows()
        .unwrap()
        .into_iter()
        .find(|(i, _, _)| *i == id)
        .unwrap();
    let mut s = v.store;
    assert_eq!(s.body(id, &bytes).unwrap().unwrap().as_slice(), unknown);
    drop(s);
    no_marker(dir.path());
}

#[test]
fn create_never_overwrites_and_encrypted_rows_fail_closed_if_moved_or_changed() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let mut v = Vault::create_encrypted(&path, PASSWORD, params()).unwrap();
    let id = ItemId::new();
    v.store.write(&[item(id, MARKER)], &[]).unwrap();
    drop(v);
    assert!(Vault::create_encrypted(&path, PASSWORD, params()).is_err());
    let conn = store::connect(&path, false).unwrap();
    let original: Vec<u8> = conn
        .query_row("SELECT envelope FROM items", [], |r| r.get(0))
        .unwrap();
    let mut corrupt = original.clone();
    let n = corrupt.len();
    corrupt[n / 2] ^= 1;
    conn.execute("UPDATE items SET envelope=?1", [corrupt])
        .unwrap();
    drop(conn);
    assert!(Vault::open_encrypted(&path, PASSWORD).is_err());
    let conn = store::connect(&path, false).unwrap();
    conn.execute(
        "UPDATE items SET envelope=?1,item_id=?2",
        params![original, ItemId::new().as_bytes().as_slice()],
    )
    .unwrap();
    drop(conn);
    assert!(Vault::open_encrypted(&path, PASSWORD).is_err());
}

#[cfg(unix)]
#[test]
fn aliases_sidecars_and_shared_parents_are_refused_without_touching_targets() {
    use std::os::unix::fs::{PermissionsExt, symlink};
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    legacy(&path);
    let alias = dir.path().join("alias.db");
    symlink(&path, &alias).unwrap();
    assert!(Vault::migrate_encrypted(&alias, PASSWORD, params()).is_err());
    std::fs::remove_file(&alias).unwrap();
    std::fs::hard_link(&path, &alias).unwrap();
    assert!(Vault::migrate_encrypted(&path, PASSWORD, params()).is_err());
    std::fs::remove_file(&alias).unwrap();
    let unrelated = dir.path().join("unrelated");
    std::fs::write(&unrelated, b"untouched").unwrap();
    let side = dir.path().join("vault.db-wal");
    symlink(&unrelated, &side).unwrap();
    assert!(Vault::migrate_encrypted(&path, PASSWORD, params()).is_err());
    assert_eq!(std::fs::read(&unrelated).unwrap(), b"untouched");
    std::fs::remove_file(side).unwrap();
    std::fs::set_permissions(dir.path(), std::fs::Permissions::from_mode(0o777)).unwrap();
    assert!(Vault::migrate_encrypted(&path, PASSWORD, params()).is_err());
    std::fs::set_permissions(dir.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let colon = dir.path().join("file:literal.db");
    drop(Vault::create_encrypted(&colon, PASSWORD, params()).unwrap());
    assert!(colon.exists());
    assert!(!dir.path().join("literal.db").exists());
}

#[test]
fn child_crash_probe() {
    let Ok(path) = std::env::var("OPENWARD_D3_CRASH_PATH") else {
        return;
    };
    let wanted = std::env::var("OPENWARD_D3_CRASH_PHASE").unwrap();
    let _ = install(Path::new(&path), PASSWORD, params(), true, |phase| {
        if format!("{phase:?}") == wanted {
            // Deliberately bypass Rust destructors without generating a core
            // dump or a native crash-report dialog on the developer machine.
            std::process::exit(79);
        }
        Ok(())
    });
    panic!("crash hook not reached");
}
#[test]
fn process_crashes_leave_a_readable_original_or_a_complete_encrypted_vault() {
    for phase in ["Staged", "Verified", "BeforeInstall", "Installed"] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let id = legacy(&path);
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "migration::tests::child_crash_probe",
                "--nocapture",
            ])
            .env("OPENWARD_D3_CRASH_PATH", &path)
            .env("OPENWARD_D3_CRASH_PHASE", phase)
            .current_dir(dir.path())
            .status()
            .unwrap();
        assert!(!status.success());
        if phase == "Installed" {
            no_marker(dir.path());
            assert_eq!(
                Vault::open_encrypted(&path, PASSWORD)
                    .unwrap()
                    .host(id)
                    .unwrap()
                    .address,
                MARKER
            );
        } else {
            assert_eq!(
                Vault::open(&path).unwrap().host(id).unwrap().address,
                MARKER
            );
            drop(Vault::migrate_encrypted(&path, PASSWORD, params()).unwrap());
            no_marker(dir.path());
        }
    }
}

#[test]
fn child_pending_journal() {
    let Ok(path) = std::env::var("OPENWARD_D3_JOURNAL_PATH") else {
        return;
    };
    let mode = std::env::var("OPENWARD_D3_JOURNAL_MODE").unwrap();
    let conn = store::connect(Path::new(&path), false).unwrap();
    conn.pragma_update(None, "journal_mode", &mode).unwrap();
    conn.pragma_update(None, "wal_autocheckpoint", 0).unwrap();
    conn.execute(
        "INSERT INTO meta VALUES ('journal-private',?1)",
        [MARKER.as_bytes()],
    )
    .unwrap();
    conn.execute("UPDATE items SET head_rev=7", []).unwrap();
    // Commit is durable, but leave the connection and its managed files open.
    std::process::exit(78);
}

#[test]
fn committed_wal_and_persist_journal_are_recovered_without_plaintext_residue() {
    for (mode, suffix) in [("WAL", "-wal"), ("PERSIST", "-journal")] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let id = legacy(&path);
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "migration::tests::child_pending_journal"])
            .env("OPENWARD_D3_JOURNAL_PATH", &path)
            .env("OPENWARD_D3_JOURNAL_MODE", mode)
            .status()
            .unwrap();
        assert_eq!(status.code(), Some(78));
        let sidecar = dir.path().join(format!("vault.db{suffix}"));
        assert!(sidecar.metadata().unwrap().len() > 0);
        let v = Vault::migrate_encrypted(&path, PASSWORD, params())
            .unwrap()
            .unlock(PASSWORD)
            .unwrap();
        assert_eq!(v.item(id).unwrap().rev, 7);
        assert_eq!(v.host(id).unwrap().address, MARKER);
        assert_eq!(
            v.metadata_value("journal-private")
                .unwrap()
                .unwrap()
                .as_slice(),
            MARKER.as_bytes()
        );
        drop(v);
        no_marker(dir.path());
    }
}

#[test]
fn concurrent_sqlite_writers_and_replacement_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let id = legacy(&path);
    drop(
        install(&path, PASSWORD, params(), true, |phase| {
            if phase == Phase::Staged {
                let c = store::connect(&path, false)?;
                c.busy_timeout(std::time::Duration::ZERO)?;
                assert!(c.execute("UPDATE items SET head_rev=99", []).is_err());
            }
            Ok(())
        })
        .unwrap(),
    );
    assert_eq!(
        Vault::open_encrypted(&path, PASSWORD)
            .unwrap()
            .item(id)
            .unwrap()
            .rev,
        1
    );

    let path = dir.path().join("replace.db");
    legacy(&path);
    let displaced = dir.path().join("displaced.db");
    assert!(
        install(&path, PASSWORD, params(), true, |phase| {
            if phase == Phase::BeforeInstall {
                std::fs::rename(&path, &displaced)?;
                std::fs::write(&path, b"new unrelated file")?;
            }
            Ok(())
        })
        .is_err()
    );
    assert_eq!(std::fs::read(&path).unwrap(), b"new unrelated file");
    assert!(Vault::open(&displaced).is_ok());
}

#[test]
fn oversized_legacy_and_encrypted_records_fail_before_decoding() {
    let dir = tempfile::tempdir().unwrap();
    for metadata in [false, true] {
        let path = dir.path().join(format!("large-{metadata}.db"));
        legacy(&path);
        let c = store::connect(&path, false).unwrap();
        if metadata {
            c.execute(
                "INSERT INTO meta VALUES ('large',zeroblob(?1))",
                [(MAX_PLAINTEXT + 129) as i64],
            )
            .unwrap();
        } else {
            c.execute(
                "UPDATE items SET envelope=zeroblob(?1)",
                [(MAX_PLAINTEXT + 129) as i64],
            )
            .unwrap();
        }
        drop(c);
        assert!(matches!(
            Vault::migrate_encrypted(&path, PASSWORD, params()),
            Err(Error::Crypto(openward_crypto::Error::Limit))
        ));
        assert_eq!(
            store::connect(&path, false)
                .unwrap()
                .pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
    }
    let path = dir.path().join("header.db");
    drop(Vault::create_encrypted(&path, PASSWORD, params()).unwrap());
    let c = store::connect(&path, false).unwrap();
    c.execute(
        "UPDATE meta SET value=zeroblob(16385) WHERE key=?1",
        [CRYPTO],
    )
    .unwrap();
    drop(c);
    assert!(matches!(
        Vault::open_locked(&path),
        Err(Error::Crypto(openward_crypto::Error::Limit))
    ));
}

#[test]
#[ignore = "release-mode measurement: cargo test --release -p openward-vault ten_thousand -- --ignored --nocapture"]
fn ten_thousand_encrypted_items_index_load() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let mut v = Vault::create_encrypted(&path, PASSWORD, params()).unwrap();
    let items: Vec<_> = (0..10_000).map(|_| item(ItemId::new(), MARKER)).collect();
    v.store.write(&items, &[]).unwrap();
    let mut locked = v.lock().unwrap();
    locked.store.unlock(PASSWORD).unwrap(); // Measure the index separately from Argon2id.
    let start = std::time::Instant::now();
    let v = Vault::load(locked.store).unwrap();
    let elapsed = start.elapsed();
    assert_eq!(v.items().count(), 10_000);
    eprintln!("10,000 encrypted item index: {elapsed:?} (password KDF excluded)");
    assert!(elapsed < std::time::Duration::from_millis(300));
}
