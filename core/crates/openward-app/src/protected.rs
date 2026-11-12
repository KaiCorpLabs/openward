//! Encrypted local documents and streaming recordings. The master-derived key
//! exists only while unlocked. Active writers retain only their recording key.
use openward_crypto::local::{LocalKey, MAX_LOCAL_BYTES};
use std::{
    fs::{self, File},
    io::{self, Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
use zeroize::Zeroizing;

fn err(_: impl std::fmt::Display) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        "protected data authentication or format failed",
    )
}
enum Mode {
    Legacy,
    Locked,
    Ready(LocalKey),
}
pub struct Files {
    root: PathBuf,
    mode: Mutex<Mode>,
}
impl Files {
    pub fn new(root: &Path, encrypted: bool) -> Arc<Self> {
        Arc::new(Self {
            root: root.to_owned(),
            mode: Mutex::new(if encrypted {
                Mode::Locked
            } else {
                Mode::Legacy
            }),
        })
    }
    pub fn legacy() -> Arc<Self> {
        Self::new(Path::new(""), false)
    }
    pub fn bind(&self, key: LocalKey) {
        *self.mode.lock().unwrap_or_else(|e| e.into_inner()) = Mode::Ready(key);
    }
    pub fn lock(&self) {
        let mut m = self.mode.lock().unwrap_or_else(|e| e.into_inner());
        if !matches!(*m, Mode::Legacy) {
            *m = Mode::Locked;
        }
    }
    pub fn encrypted(&self) -> bool {
        !matches!(
            *self.mode.lock().unwrap_or_else(|e| e.into_inner()),
            Mode::Legacy
        )
    }
    pub fn available(&self) -> bool {
        !matches!(
            *self.mode.lock().unwrap_or_else(|e| e.into_inner()),
            Mode::Locked
        )
    }
    pub fn document(&self, name: &str) -> io::Result<Option<Zeroizing<String>>> {
        let m = self.mode.lock().unwrap_or_else(|e| e.into_inner());
        if matches!(*m, Mode::Locked) {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        let path = self.doc_path(name)?;
        let Some(bytes) = read_optional(&path, MAX_LOCAL_BYTES + 45)? else {
            return Ok(None);
        };
        let clear = match &*m {
            Mode::Legacy => {
                if bytes.starts_with(b"OWLD") {
                    return Err(err("encrypted data in legacy mode"));
                }
                Zeroizing::new(bytes)
            }
            Mode::Locked => return Err(io::ErrorKind::PermissionDenied.into()),
            Mode::Ready(k) => k.open(name.as_bytes(), &bytes).map_err(err)?,
        };
        let mut json = serde_json::Deserializer::from_slice(&clear);
        use serde::Deserialize;
        let valid = serde::de::IgnoredAny::deserialize(&mut json)
            .and_then(|_| json.end())
            .is_ok();
        if !valid {
            let quarantine = self.root.join(format!("{name}.json.bad"));
            if !quarantine.exists() {
                let protected = match &*m {
                    Mode::Ready(k) => k.seal(name.as_bytes(), &clear).map_err(err)?,
                    _ => clear.to_vec(),
                };
                atomic_new(&quarantine, &protected)?;
            }
            return Ok(None);
        }
        std::str::from_utf8(&clear)
            .map(|s| Zeroizing::new(s.to_owned()))
            .map(Some)
            .map_err(err)
    }
    pub fn write_document(&self, name: &str, text: &str) -> io::Result<()> {
        if text.len() > MAX_LOCAL_BYTES {
            return Err(err("document too large"));
        }
        let mut json = serde_json::Deserializer::from_str(text);
        use serde::Deserialize;
        serde::de::IgnoredAny::deserialize(&mut json)
            .and_then(|_| json.end())
            .map_err(err)?;
        let path = self.doc_path(name)?;
        let m = self.mode.lock().unwrap_or_else(|e| e.into_inner());
        let bytes = match &*m {
            Mode::Legacy => text.as_bytes().to_vec(),
            Mode::Ready(k) => k.seal(name.as_bytes(), text.as_bytes()).map_err(err)?,
            Mode::Locked => return Err(io::ErrorKind::PermissionDenied.into()),
        };
        atomic(&path, &bytes)
    }
    pub fn erase_document(&self, name: &str) -> io::Result<()> {
        self.doc_path(name)?;
        let mode = self.mode.lock().unwrap_or_else(|e| e.into_inner());
        if matches!(*mode, Mode::Locked) {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        for suffix in [".json", ".json.tmp", ".json.bad"] {
            match fs::remove_file(self.root.join(format!("{name}{suffix}"))) {
                Ok(()) => {}
                Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }
    fn doc_path(&self, name: &str) -> io::Result<PathBuf> {
        if !["history", "recent"].contains(&name) {
            return Err(err("unknown document"));
        }
        Ok(self.root.join(format!("{name}.json")))
    }
    pub fn migrate_documents(&self) -> io::Result<()> {
        for name in ["history", "recent"] {
            for suffix in [".json", ".json.tmp", ".json.bad"] {
                let path = self.root.join(format!("{name}{suffix}"));
                let Some(bytes) = read_optional(&path, MAX_LOCAL_BYTES + 45)? else {
                    continue;
                };
                let bytes = Zeroizing::new(bytes);
                if bytes.starts_with(b"OWLD") {
                    let m = self.mode.lock().unwrap_or_else(|e| e.into_inner());
                    let Mode::Ready(k) = &*m else {
                        return Err(err("locked"));
                    };
                    k.open(name.as_bytes(), &bytes).map_err(err)?;
                    continue;
                }
                // Preserve malformed and staged legacy data encrypted as well; never
                // create a new plaintext .bad copy and never discard source on error.
                let sealed = {
                    let m = self.mode.lock().unwrap_or_else(|e| e.into_inner());
                    let Mode::Ready(k) = &*m else {
                        return Err(err("locked"));
                    };
                    let b = k.seal(name.as_bytes(), &bytes).map_err(err)?;
                    k.open(name.as_bytes(), &b).map_err(err)?;
                    b
                };
                atomic(&path, &sealed)?;
            }
        }
        Ok(())
    }
    pub fn new_recording(&self, dir: &Path, id: &str) -> io::Result<Option<Arc<LocalKey>>> {
        let m = self.mode.lock().unwrap_or_else(|e| e.into_inner());
        match &*m {
            Mode::Legacy => Ok(None),
            Mode::Locked => Err(io::ErrorKind::PermissionDenied.into()),
            Mode::Ready(master) => {
                valid_id(id)?;
                let key = Arc::new(LocalKey::generate().map_err(err)?);
                atomic_new(
                    &dir.join(format!("{id}.key")),
                    &master.seal(id.as_bytes(), key.secret()).map_err(err)?,
                )?;
                Ok(Some(key))
            }
        }
    }
    pub fn recording_key(&self, dir: &Path, id: &str) -> io::Result<Option<Arc<LocalKey>>> {
        let m = self.mode.lock().unwrap_or_else(|e| e.into_inner());
        match &*m {
            Mode::Legacy => Ok(None),
            Mode::Locked => Err(io::ErrorKind::PermissionDenied.into()),
            Mode::Ready(master) => {
                valid_id(id)?;
                let b = read_optional(&dir.join(format!("{id}.key")), 77)?
                    .ok_or_else(|| err("missing recording key"))?;
                let clear = master.open(id.as_bytes(), &b).map_err(err)?;
                if clear.len() != 32 {
                    return Err(err("invalid recording key"));
                }
                let mut key = Zeroizing::new([0; 32]);
                key.copy_from_slice(&clear);
                Ok(Some(Arc::new(LocalKey::from_secret(key))))
            }
        }
    }
}
pub(crate) fn valid_id(id: &str) -> io::Result<()> {
    let parsed = id.parse::<crate::vault::proto::ItemId>().map_err(err)?;
    if parsed.to_string() != id {
        return Err(err("invalid log id"));
    }
    Ok(())
}
pub(crate) fn encrypted_prefix(path: &Path) -> io::Result<bool> {
    let md = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(e) => return Err(e),
    };
    if !md.is_file() {
        return Err(err("invalid protected file"));
    }
    let mut bytes = Vec::new();
    File::open(path)?.take(5).read_to_end(&mut bytes)?;
    Ok(bytes.starts_with(b"OWLD") || bytes.starts_with(b"OWLF"))
}
pub(crate) fn read_optional(path: &Path, max: usize) -> io::Result<Option<Vec<u8>>> {
    let md = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e),
    };
    if !md.is_file() || md.len() > max as u64 {
        return Err(err("invalid protected file"));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if md.nlink() != 1 {
            return Err(err("linked protected file"));
        }
    }
    let mut f = File::open(path)?;
    let mut b = Vec::new();
    Read::by_ref(&mut f)
        .take(max as u64 + 1)
        .read_to_end(&mut b)?;
    if b.len() > max {
        return Err(err("oversized file"));
    }
    Ok(Some(b))
}
// Make newly installed wrappers durable before any recording can use their
// keys. As in the vault installer, Unix needs the directory synced as well.
fn sync_parent(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    {
        File::open(path.parent().ok_or_else(|| err("missing parent"))?)?.sync_all()
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        Ok(())
    }
}
pub(crate) fn atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut f =
        tempfile::NamedTempFile::new_in(path.parent().ok_or_else(|| err("missing parent"))?)?;
    f.write_all(bytes)?;
    f.as_file().sync_all()?;
    f.persist(path).map_err(|e| e.error)?;
    sync_parent(path)
}
fn atomic_new(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut f =
        tempfile::NamedTempFile::new_in(path.parent().ok_or_else(|| err("missing parent"))?)?;
    f.write_all(bytes)?;
    f.as_file().sync_all()?;
    f.persist_noclobber(path).map_err(|e| e.error)?;
    sync_parent(path)
}

const CHUNK: usize = 64 * 1024;
const STREAM: &[u8] = b"OWLF\x01";
pub(crate) enum Writer {
    Plain(File),
    Sealed(StreamWriter),
}
impl Writer {
    pub fn create(path: &Path, key: Option<Arc<LocalKey>>) -> io::Result<Self> {
        let file = crate::logs::create(path)?;
        match key {
            None => Ok(Self::Plain(file)),
            Some(key) => Ok(Self::Sealed(StreamWriter::new(file, key, label(path)?)?)),
        }
    }
    pub fn finish(&mut self) -> io::Result<()> {
        match self {
            Self::Plain(f) => f.sync_all(),
            Self::Sealed(s) => s.finish(),
        }
    }
}
impl Write for Writer {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        match self {
            Self::Plain(f) => f.write(b),
            Self::Sealed(s) => s.write(b),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        match self {
            Self::Plain(f) => f.flush(),
            Self::Sealed(s) => s.flush(),
        }
    }
}
fn label(path: &Path) -> io::Result<Vec<u8>> {
    Ok(path
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| err("invalid name"))?
        .as_bytes()
        .to_vec())
}
pub(crate) struct StreamWriter {
    file: File,
    key: Arc<LocalKey>,
    label: Vec<u8>,
    header: Vec<u8>,
    seq: u64,
    done: bool,
}
impl StreamWriter {
    fn new(mut file: File, key: Arc<LocalKey>, label: Vec<u8>) -> io::Result<Self> {
        let mut h = STREAM.to_vec();
        let mut random = [0; 16];
        getrandom::fill(&mut random).map_err(err)?;
        h.extend(random);
        file.write_all(&h)?;
        Ok(Self {
            file,
            key,
            label,
            header: h,
            seq: 0,
            done: false,
        })
    }
    fn frame(&mut self, b: &[u8]) -> io::Result<()> {
        let aad = [self.label.as_slice(), &self.header, &self.seq.to_be_bytes()].concat();
        let ct = self.key.seal(&aad, b).map_err(err)?;
        self.file.write_all(&(ct.len() as u32).to_be_bytes())?;
        self.file.write_all(&ct)?;
        self.seq = self
            .seq
            .checked_add(1)
            .ok_or_else(|| err("stream exhausted"))?;
        Ok(())
    }
    fn finish(&mut self) -> io::Result<()> {
        if !self.done {
            self.frame(&[1])?;
            self.file.sync_all()?;
            self.done = true;
        }
        Ok(())
    }
}
impl Write for StreamWriter {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        if self.done {
            return Err(err("closed stream"));
        }
        let n = b.len().min(CHUNK);
        if n == 0 {
            return Ok(0);
        }
        let mut clear = Zeroizing::new(Vec::with_capacity(n + 1));
        clear.push(0);
        clear.extend(&b[..n]);
        self.frame(&clear)?;
        Ok(n)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}

struct StreamReader {
    file: File,
    key: Arc<LocalKey>,
    label: Vec<u8>,
    header: Vec<u8>,
    seq: u64,
    buf: Zeroizing<Vec<u8>>,
    at: usize,
    ended: bool,
    partial: bool,
}
impl StreamReader {
    fn new(mut file: File, key: Arc<LocalKey>, label: Vec<u8>, partial: bool) -> io::Result<Self> {
        let mut h = vec![0; 21];
        file.read_exact(&mut h)?;
        if !h.starts_with(STREAM) {
            return Err(err("invalid stream"));
        }
        Ok(Self {
            file,
            key,
            label,
            header: h,
            seq: 0,
            buf: Zeroizing::new(Vec::new()),
            at: 0,
            ended: false,
            partial,
        })
    }
    fn next(&mut self) -> io::Result<bool> {
        if self.ended {
            return Ok(false);
        }
        let mut len = [0; 4];
        match self.file.read_exact(&mut len) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof && self.partial => return Ok(false),
            Err(e) => return Err(e),
        }
        let n = u32::from_be_bytes(len) as usize;
        if !(46..=CHUNK + 46).contains(&n) {
            return Err(err("invalid frame length"));
        }
        let mut ct = vec![0; n];
        match self.file.read_exact(&mut ct) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof && self.partial => return Ok(false),
            Err(e) => return Err(e),
        }
        let aad = [self.label.as_slice(), &self.header, &self.seq.to_be_bytes()].concat();
        let clear = self.key.open(&aad, &ct).map_err(err)?;
        self.seq = self
            .seq
            .checked_add(1)
            .ok_or_else(|| err("stream exhausted"))?;
        match clear.first() {
            Some(0) => {
                self.buf = clear;
                self.at = 1;
                Ok(true)
            }
            Some(1) if clear.len() == 1 => {
                let mut extra = [0];
                if self.file.read(&mut extra)? != 0 {
                    return Err(err("trailing stream data"));
                }
                self.ended = true;
                Ok(false)
            }
            _ => Err(err("invalid frame")),
        }
    }
}
impl Read for StreamReader {
    fn read(&mut self, b: &mut [u8]) -> io::Result<usize> {
        if b.is_empty() {
            return Ok(0);
        }
        while self.at == self.buf.len() {
            if !self.next()? {
                return Ok(0);
            }
        }
        let n = b.len().min(self.buf.len() - self.at);
        b[..n].copy_from_slice(&self.buf[self.at..self.at + n]);
        self.at += n;
        Ok(n)
    }
}
pub(crate) fn reader(
    path: &Path,
    key: Option<Arc<LocalKey>>,
    partial: bool,
) -> io::Result<Box<dyn Read>> {
    let md = fs::symlink_metadata(path)?;
    if !md.is_file() {
        return Err(err("invalid recording"));
    }
    let mut file = File::open(path)?;
    match key {
        None => Ok(Box::new(file)),
        Some(key) => {
            // Validate every available authenticated frame before parsers that
            // deliberately tolerate a cut gzip/JSON line can consume any plaintext.
            let mut check =
                StreamReader::new(file.try_clone()?, Arc::clone(&key), label(path)?, partial)?;
            io::copy(&mut check, &mut io::sink())?;
            file.seek(SeekFrom::Start(0))?;
            Ok(Box::new(StreamReader::new(
                file,
                key,
                label(path)?,
                partial,
            )?))
        }
    }
}
pub(crate) fn seal_file(path: &Path, key: Arc<LocalKey>) -> io::Result<()> {
    let md = fs::symlink_metadata(path)?;
    if !md.is_file() {
        return Err(err("invalid recording"));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if md.nlink() != 1 {
            return Err(err("linked recording"));
        }
    }
    let mut source = File::open(path)?;
    let mut magic = [0; 5];
    let n = source.read(&mut magic)?;
    source.seek(SeekFrom::Start(0))?;
    if n == 5 && magic == STREAM {
        return Ok(());
    }
    let mut temp =
        tempfile::NamedTempFile::new_in(path.parent().ok_or_else(|| err("missing parent"))?)?;
    {
        let mut out =
            StreamWriter::new(temp.as_file().try_clone()?, Arc::clone(&key), label(path)?)?;
        io::copy(&mut source, &mut out)?;
        out.finish()?;
    }
    temp.flush()?;
    temp.as_file_mut().seek(SeekFrom::Start(0))?;
    // The staged ciphertext is authenticated in full before replacing source.
    let mut check = StreamReader::new(
        temp.as_file().try_clone()?,
        Arc::clone(&key),
        label(path)?,
        false,
    )?;
    io::copy(&mut check, &mut io::sink())?;
    temp.persist(path).map_err(|e| e.error)?;
    sync_parent(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        App, Local,
        logs::{Begin, End, Place},
        vault::Vault,
    };
    use openward_crypto::{password::KdfParams, unlock::RecoveryKit};
    fn fixture() -> (tempfile::TempDir, App) {
        let d = tempfile::tempdir().unwrap();
        let path = d.path().join("vault.db");
        drop(Vault::open(&path).unwrap());
        drop(
            Vault::migrate_with_recovery(
                &path,
                b"public password",
                KdfParams::new(65536, 1).unwrap(),
                &RecoveryKit::generate().unwrap(),
            )
            .unwrap(),
        );
        let app = App::open_as(
            d.path(),
            Local {
                home: d.path().into(),
                user: "fixture".into(),
                ssh_dir: d.path().join("ssh"),
                system_ssh_dir: d.path().join("system"),
                agent: None,
            },
        )
        .unwrap();
        (d, app)
    }
    fn begin() -> Begin {
        Begin {
            place: Place::Address("private.example".into()),
            label: "private host TEST".into(),
            address: "private.example".into(),
            marking: None,
            system: None,
            tmux: false,
            record: true,
            cols: 80,
            rows: 24,
            term: "xterm".into(),
        }
    }
    #[test]
    fn per_recording_key_continues_after_lock_while_documents_and_index_are_unavailable() {
        let (d, app) = fixture();
        app.security().unlock(b"public password").unwrap();
        app.protected()
            .write_document(
                "history",
                r#"{"commands":[{"command":"private-command-TEST"}]}"#,
            )
            .unwrap();
        let log = app.logs().begin(begin()).unwrap();
        let id = log.id();
        log.output(b"before-lock-TEST\r\n");
        app.lock_vault().unwrap();
        assert!(!app.protected().available());
        assert!(app.logs().list().is_empty());
        assert!(app.protected().document("history").is_err());
        assert!(app.protected().write_document("recent", "{}").is_err());
        assert!(app.logs().read(&id).is_err());
        assert!(app.logs().begin(begin()).is_err());
        log.output(b"after-lock-TEST\r\n");
        log.finish(End::Closed);
        assert!(app.logs().list().is_empty());
        app.security().unlock(b"public password").unwrap();
        assert!(
            app.protected()
                .document("history")
                .unwrap()
                .unwrap()
                .contains("private-command")
        );
        let text = app.logs().plain_text(&id).unwrap();
        assert!(text.contains("before-lock-TEST"));
        assert!(text.contains("after-lock-TEST"));
        for file in fs::read_dir(d.path().join("logs")).unwrap() {
            let p = file.unwrap().path();
            let b = fs::read(&p).unwrap();
            for needle in [
                b"private host TEST".as_slice(),
                b"private.example",
                b"after-lock-TEST",
            ] {
                assert!(
                    !b.windows(needle.len()).any(|w| w == needle),
                    "plaintext in a managed log file"
                );
            }
        }
        assert!(app.logs().delete(&id).unwrap());
        assert!(!d.path().join("logs").join(format!("{id}.key")).exists());
    }
    #[test]
    fn migration_encrypts_legacy_documents_aliases_and_recordings_before_unlock_is_published() {
        let d = tempfile::tempdir().unwrap();
        let logs = crate::Logs::open(&d.path().join("logs"), Default::default()).unwrap();
        let s = logs.begin(begin()).unwrap();
        let id = s.id();
        s.output(b"legacy-private-output-TEST\r\n");
        s.finish(End::Closed);
        drop(s);
        drop(logs);
        for name in [
            "history.json",
            "history.json.tmp",
            "history.json.bad",
            "recent.json",
        ] {
            fs::write(d.path().join(name), b"legacy-private-document-TEST").unwrap();
        }
        let path = d.path().join("vault.db");
        drop(Vault::open(&path).unwrap());
        drop(
            Vault::migrate_with_recovery(
                &path,
                b"public password",
                KdfParams::new(65536, 1).unwrap(),
                &RecoveryKit::generate().unwrap(),
            )
            .unwrap(),
        );
        let app = App::open_as(
            d.path(),
            Local {
                home: d.path().into(),
                user: "fixture".into(),
                ssh_dir: d.path().join("ssh"),
                system_ssh_dir: d.path().join("system"),
                agent: None,
            },
        )
        .unwrap();
        assert!(app.logs().list().is_empty());
        app.security().unlock(b"public password").unwrap();
        assert!(
            app.logs()
                .plain_text(&id)
                .unwrap()
                .contains("legacy-private-output")
        );
        for name in [
            "history.json",
            "history.json.tmp",
            "history.json.bad",
            "recent.json",
        ] {
            let b = fs::read(d.path().join(name)).unwrap();
            assert!(b.starts_with(b"OWLD\x01"));
            assert!(!b.windows(7).any(|w| w == b"legacy-"));
        }
    }
    #[test]
    fn frame_authentication_rejects_tamper_wrong_names_and_truncated_closed_streams() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("record.cast.gz");
        let key = Arc::new(LocalKey::generate().unwrap());
        let mut w = Writer::create(&p, Some(Arc::clone(&key))).unwrap();
        w.write_all(b"secret output TEST").unwrap();
        w.finish().unwrap();
        drop(w);
        let mut out = Vec::new();
        reader(&p, Some(Arc::clone(&key)), false)
            .unwrap()
            .read_to_end(&mut out)
            .unwrap();
        assert_eq!(out, b"secret output TEST");
        let original = fs::read(&p).unwrap();
        let other = d.path().join("record.txt.gz");
        fs::write(&other, &original).unwrap();
        assert!(reader(&other, Some(Arc::clone(&key)), false).is_err());
        let mut altered = original.clone();
        altered[60] ^= 1;
        fs::write(&p, altered).unwrap();
        assert!(reader(&p, Some(Arc::clone(&key)), true).is_err());
        fs::write(&p, &original[..original.len() - 1]).unwrap();
        assert!(reader(&p, Some(Arc::clone(&key)), false).is_err());
        assert!(reader(&p, Some(key), true).is_ok());
    }
    #[test]
    fn corrupt_document_fails_closed_and_preserves_the_original_bytes() {
        let (d, app) = fixture();
        app.security().unlock(b"public password").unwrap();
        app.protected().write_document("history", "{}").unwrap();
        app.lock_vault().unwrap();
        let path = d.path().join("history.json");
        let mut b = fs::read(&path).unwrap();
        *b.last_mut().unwrap() ^= 1;
        fs::write(&path, &b).unwrap();
        assert!(app.security().unlock(b"public password").is_err());
        assert!(!app.protected().available());
        assert!(app.vault().is_locked());
        assert_eq!(fs::read(path).unwrap(), b);
    }

    #[test]
    fn a_missing_recording_wrapper_fails_closed_without_replacing_it() {
        let (d, app) = fixture();
        app.security().unlock(b"public password").unwrap();
        let log = app.logs().begin(begin()).unwrap();
        let id = log.id();
        log.output(b"private-output-TEST\r\n");
        log.finish(End::Closed);
        app.lock_vault().unwrap();
        let wrapper = d.path().join("logs").join(format!("{id}.key"));
        fs::remove_file(&wrapper).unwrap();
        let cast = d.path().join("logs").join(format!("{id}.cast.gz"));
        let original = fs::read(&cast).unwrap();
        assert!(app.security().unlock(b"public password").is_err());
        assert!(!wrapper.exists());
        assert_eq!(fs::read(cast).unwrap(), original);
        assert!(app.vault().is_locked());
    }

    #[test]
    fn format_barrier_is_durable_and_malformed_json_is_quarantined_as_ciphertext() {
        let (d, app) = fixture();
        fs::write(d.path().join("history.json"), b"invalid-private-json-TEST").unwrap();
        assert!(app.protected().document("recent").is_err());
        app.security().unlock(b"public password").unwrap();
        assert!(app.protected().document("history").unwrap().is_none());
        let quarantine = fs::read(d.path().join("history.json.bad")).unwrap();
        assert!(quarantine.starts_with(b"OWLD\x01"));
        app.protected().write_document("history", "{}").unwrap();
        assert_eq!(
            fs::read(d.path().join("history.json.bad")).unwrap(),
            quarantine
        );
        let c = rusqlite::Connection::open(d.path().join("vault.db")).unwrap();
        let version: i64 = c
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, 3);
        drop(c);
        drop(app);
        let mut v = Vault::open_session(&d.path().join("vault.db")).unwrap();
        v.unlock_in_place(b"public password").unwrap();
        assert!(v.is_encrypted());
    }

    #[cfg(unix)]
    #[test]
    fn migration_refuses_symlinks_and_preserves_external_files() {
        let (d, app) = fixture();
        let external = d.path().join("external");
        fs::write(&external, b"private outside TEST").unwrap();
        std::os::unix::fs::symlink(&external, d.path().join("recent.json")).unwrap();
        assert!(app.security().unlock(b"public password").is_err());
        assert!(app.vault().is_locked());
        assert_eq!(fs::read(external).unwrap(), b"private outside TEST");
    }

    #[test]
    fn enabling_encryption_requires_legacy_recorders_to_close_first() {
        let d = tempfile::tempdir().unwrap();
        let app = App::open_as(
            d.path(),
            Local {
                home: d.path().into(),
                user: "fixture".into(),
                ssh_dir: d.path().join("ssh"),
                system_ssh_dir: d.path().join("system"),
                agent: None,
            },
        )
        .unwrap();
        let session = app.logs().begin(begin()).unwrap();
        let setup = app
            .security()
            .prepare_setup(Zeroizing::new(
                "Meteor-7-Parchment-Unfurl-Quartz-92!".into(),
            ))
            .unwrap();
        let groups: Vec<_> = setup.kit.split('-').collect();
        assert!(
            app.security()
                .complete_setup(groups[3], groups[12])
                .is_err()
        );
        assert_eq!(
            app.security().status().phase,
            crate::security::Phase::Legacy
        );
        assert!(!app.vault().is_encrypted());
        session.output(b"legacy session still usable\r\n");
        session.finish(End::Closed);
    }
}
