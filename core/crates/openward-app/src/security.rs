//! Application authority for vault state and synchronous UI access. Network
//! connections outlive locking; access to their UI is separately gated.
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, RwLock, RwLockReadGuard};
use std::time::{Duration, Instant};

use openward_vault::{Error, Result, Vault};

pub mod native;
mod recovery_document;

pub type Waker = Arc<dyn Fn() + Send + Sync>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Legacy,
    Locked,
    Unlocked,
    Changing,
    LegacyPaused,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Status {
    pub phase: Phase,
    pub auto_lock_seconds: u64,
    pub native_enabled: bool,
    pub recovery_available: bool,
}

/// Read leases serialize frame/metadata reads and input enqueueing with lock.
/// Async operations retain an epoch ticket and check it after awaiting, never
/// holding this synchronous lease across a network await.
pub struct AccessGate {
    state: RwLock<(u64, bool)>,
}
impl AccessGate {
    fn new(open: bool) -> Self {
        Self {
            state: RwLock::new((0, open)),
        }
    }
    pub fn read(&self) -> Result<Access<'_>> {
        let guard = self.state.read().unwrap_or_else(|e| e.into_inner());
        if !guard.1 {
            return Err(Error::Locked);
        }
        Ok(Access(guard))
    }
    pub fn is_open(&self) -> bool {
        self.state.try_read().is_ok_and(|s| s.1)
    }
    pub fn ticket(&self) -> Result<u64> {
        Ok(self.read()?.0.0)
    }
    pub fn check(&self, ticket: u64) -> Result<()> {
        let access = self.read()?;
        if access.0.0 != ticket {
            return Err(Error::Locked);
        }
        Ok(())
    }
    fn epoch(&self) -> u64 {
        self.state.read().unwrap_or_else(|e| e.into_inner()).0
    }
    fn close_when(&self, condition: impl FnOnce() -> bool) -> bool {
        let mut state = self.state.write().unwrap_or_else(|e| e.into_inner());
        if !condition() {
            return false;
        }
        state.0 = state.0.checked_add(1).expect("access epoch exhausted");
        state.1 = false;
        true
    }
    fn open(&self, epoch: u64) -> bool {
        let mut state = self.state.write().unwrap_or_else(|e| e.into_inner());
        if state.0 != epoch {
            return false;
        }
        state.1 = true;
        true
    }
}
pub struct Access<'a>(RwLockReadGuard<'a, (u64, bool)>);
impl Access<'_> {
    pub fn epoch(&self) -> u64 {
        self.0.0
    }
}

enum SetupKind {
    Migration,
    Rotation(u64),
}
struct Setup {
    kind: SetupKind,
    password: zeroize::Zeroizing<String>,
    kit: openward_crypto::unlock::RecoveryKit,
}
pub struct SetupView {
    pub kit: zeroize::Zeroizing<String>,
    pub confirm_groups: [usize; 2],
}

pub struct VaultSession {
    vault: Arc<Mutex<Vault>>,
    path: PathBuf,
    gate: Arc<AccessGate>,
    phase: AtomicU8,
    timeout: AtomicU64,
    native_enabled: AtomicBool,
    recovery_available: AtomicBool,
    operation: Mutex<()>,
    setup: Mutex<Option<Setup>>,
    activity: Mutex<Instant>,
    wake: Mutex<Option<Waker>>,
    vault_wake: Mutex<Option<Waker>>,
}
impl VaultSession {
    pub fn open(path: &Path) -> Result<Self> {
        let vault = Vault::open_session(path)?;
        let phase = if vault.is_encrypted() {
            Phase::Locked
        } else {
            Phase::Legacy
        };
        // A damaged optional factor must not disable the independent password
        // path. Invalid native identifiers are never sent to an OS store.
        let native_enabled = vault.native_id().ok().flatten().is_some();
        let recovery_available = vault.has_recovery().unwrap_or(false);
        let policy_path = path.with_extension("security.json");
        let timeout = match std::fs::metadata(&policy_path) {
            Ok(m) if m.len() <= 32 => std::fs::read_to_string(&policy_path)?
                .trim()
                .parse::<u64>()
                .ok()
                .filter(|s| *s <= 86400)
                .unwrap_or(900),
            _ => 900,
        };
        Ok(Self {
            vault: Arc::new(Mutex::new(vault)),
            path: path.to_owned(),
            gate: Arc::new(AccessGate::new(phase == Phase::Legacy)),
            phase: AtomicU8::new(phase as u8),
            timeout: AtomicU64::new(timeout),
            native_enabled: AtomicBool::new(native_enabled),
            recovery_available: AtomicBool::new(recovery_available),
            operation: Mutex::new(()),
            setup: Mutex::new(None),
            activity: Mutex::new(Instant::now()),
            wake: Mutex::new(None),
            vault_wake: Mutex::new(None),
        })
    }
    pub fn vault(&self) -> Arc<Mutex<Vault>> {
        Arc::clone(&self.vault)
    }
    fn guard(&self) -> MutexGuard<'_, Vault> {
        self.vault.lock().unwrap_or_else(|e| e.into_inner())
    }
    pub fn access(&self) -> Result<MutexGuard<'_, Vault>> {
        let vault = self.guard();
        if vault.is_locked() {
            return Err(Error::Locked);
        }
        Ok(vault)
    }
    pub fn gate(&self) -> Arc<AccessGate> {
        Arc::clone(&self.gate)
    }
    pub fn status(&self) -> Status {
        let phase = match self.phase.load(Ordering::Acquire) {
            0 => Phase::Legacy,
            1 => Phase::Locked,
            2 => Phase::Unlocked,
            3 => Phase::Changing,
            _ => Phase::LegacyPaused,
        };
        Status {
            phase,
            auto_lock_seconds: self.timeout.load(Ordering::Acquire),
            native_enabled: self.native_enabled.load(Ordering::Acquire),
            recovery_available: self.recovery_available.load(Ordering::Acquire),
        }
    }
    fn phase(&self, phase: Phase) {
        self.phase.store(phase as u8, Ordering::Release);
    }
    pub fn watch(&self, wake: Waker) {
        let mut current = self.wake.lock().unwrap_or_else(|e| e.into_inner());
        *current = Some(wake);
        // Initial snapshot and subsequent emissions share one serialization
        // lock: an old unlocked snapshot cannot arrive after a lock event.
        if let Some(wake) = current.as_ref() {
            wake();
        }
    }
    fn notify(&self) {
        let current = self.wake.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(wake) = current.as_ref() {
            wake();
        }
    }
    pub fn watch_vault(&self, wake: Waker) {
        *self.vault_wake.lock().unwrap_or_else(|e| e.into_inner()) = Some(Arc::clone(&wake));
        if let Ok(mut vault) = self.access() {
            vault.on_change(move || wake());
        }
    }
    pub fn activity(&self) {
        if let Ok(_access) = self.gate.read() {
            *self.activity.lock().unwrap_or_else(|e| e.into_inner()) = Instant::now();
        }
    }
    pub fn set_auto_lock(&self, seconds: u64) -> Result<()> {
        let _access = self.gate.read()?;
        if seconds > 86400 {
            return Err(Error::Invalid("auto-lock exceeds one day"));
        }
        use std::io::Write;
        let path = self.path.with_extension("security.json");
        let mut file = tempfile::NamedTempFile::new_in(
            path.parent().ok_or(Error::Invalid("invalid vault path"))?,
        )?;
        write!(file, "{seconds}")?;
        file.as_file().sync_all()?;
        file.persist(path).map_err(|e| e.error)?;
        self.timeout.store(seconds, Ordering::Release);
        *self.activity.lock().unwrap_or_else(|e| e.into_inner()) = Instant::now();
        drop(_access);
        self.notify();
        Ok(())
    }
    fn authenticate(&self, operation: impl FnOnce(&mut Vault) -> Result<()>) -> Result<()> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("authentication is already in progress"))?;
        let epoch = self.gate.epoch();
        if self.status().phase == Phase::Unlocked {
            self.notify();
            return Ok(());
        }
        if matches!(self.status().phase, Phase::Legacy | Phase::LegacyPaused) {
            return Err(Error::Invalid("the vault is not encrypted"));
        }
        self.phase(Phase::Changing);
        self.notify();
        let mut vault = self.guard();
        let result = operation(&mut vault);
        self.finish_auth(epoch, &mut vault, result)
    }
    fn finish_auth(&self, epoch: u64, vault: &mut Vault, result: Result<()>) -> Result<()> {
        let result = if result.is_ok() && self.gate.open(epoch) {
            *self.activity.lock().unwrap_or_else(|e| e.into_inner()) = Instant::now();
            self.phase(Phase::Unlocked);
            Ok(())
        } else {
            vault.lock_in_place()?;
            self.phase(Phase::Locked);
            result.and(Err(Error::Locked))
        };
        self.notify();
        result
    }
    pub fn unlock(&self, password: &[u8]) -> Result<()> {
        self.authenticate(|v| v.unlock_in_place(password))
    }
    pub fn recover(&self, text: &str) -> Result<()> {
        let kit = openward_crypto::unlock::RecoveryKit::parse(text)?;
        self.authenticate(|v| v.unlock_recovery(&kit))
    }
    pub fn unlock_native(&self, store: &dyn native::Store) -> Result<()> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("authentication is already in progress"))?;
        let epoch = self.gate.epoch();
        if self.status().phase == Phase::Unlocked {
            return Ok(());
        }
        let id = self
            .guard()
            .native_id()?
            .ok_or(Error::Invalid("native unlock is not enabled"))?;
        self.phase(Phase::Changing);
        self.notify();
        // No vault mutex or access lease is held during a native prompt.
        let result = store.read(&id).map_err(native_error);
        let mut vault = self.guard();
        let result = result.and_then(|key| {
            if self.gate.epoch() != epoch {
                return Err(Error::Locked);
            }
            vault.unlock_native(&key)
        });
        self.finish_auth(epoch, &mut vault, result)
    }
    pub fn enable_native(&self, store: &dyn native::Store, linux_ack: bool) -> Result<()> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("authentication is already in progress"))?;
        let epoch = self.gate.ticket()?;
        if store.kind() == native::Kind::SessionKeyring && !linux_ack {
            return Err(Error::Invalid(
                "acknowledge session keyring protection first",
            ));
        }
        let prefix = self.guard().native_namespace()?;
        let mut random = [0u8; 16];
        getrandom::fill(&mut random)
            .map_err(|_| Error::Invalid("secure randomness unavailable"))?;
        let suffix: String = random.iter().map(|b| format!("{b:02x}")).collect();
        let id = format!("{prefix}{suffix}");
        let key = store.create(&id).map_err(native_error)?;
        let result = (|| {
            let _access = self.gate.read()?;
            if _access.epoch() != epoch {
                return Err(Error::Locked);
            }
            let mut vault = self.guard();
            let old = vault.native_id().ok().flatten();
            vault.enroll_native(&id, &key)?;
            self.native_enabled.store(true, Ordering::Release);
            Ok(old)
        })();
        match result {
            Ok(old) => {
                if let Some(old) = old {
                    let _ = store.remove(&old);
                }
                self.notify();
                Ok(())
            }
            Err(e) => {
                let _ = store.remove(&id);
                Err(e)
            }
        }
    }
    pub fn disable_native(&self, store: &dyn native::Store) -> Result<()> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("authentication is already in progress"))?;
        let _access = self.gate.read()?;
        let id = {
            let mut v = self.guard();
            let id = v.native_id().ok().flatten();
            v.disable_native()?;
            id
        };
        self.native_enabled.store(false, Ordering::Release);
        drop(_access);
        self.notify();
        if let Some(id) = id {
            store.remove(&id).map_err(native_error)?;
        }
        Ok(())
    }
    pub fn password_score(password: &str) -> Result<u8> {
        if password.chars().count() > 128 {
            return Err(Error::Invalid("password exceeds 128 characters"));
        }
        Ok(u8::from(zxcvbn::zxcvbn(password, &[]).score()))
    }
    pub fn prepare_setup(&self, password: zeroize::Zeroizing<String>) -> Result<SetupView> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("authentication is already in progress"))?;
        let _access = self.gate.read()?;
        if self.status().phase != Phase::Legacy {
            return Err(Error::Invalid("the vault is already encrypted"));
        }
        if password.chars().count() < 12 || Self::password_score(&password)? < 3 {
            return Err(Error::Invalid(
                "choose a stronger master password (at least 12 characters)",
            ));
        }
        let kit = openward_crypto::unlock::RecoveryKit::generate()?;
        let text = kit.text();
        *self.setup.lock().unwrap_or_else(|e| e.into_inner()) = Some(Setup {
            kind: SetupKind::Migration,
            password,
            kit,
        });
        Ok(SetupView {
            kit: text,
            confirm_groups: [3, 12],
        })
    }
    pub fn cancel_setup(&self) {
        self.setup.lock().unwrap_or_else(|e| e.into_inner()).take();
    }
    pub fn complete_setup(&self, group3: &str, group12: &str) -> Result<()> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("authentication is already in progress"))?;
        let setup = self
            .setup
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
            .ok_or(Error::Invalid("restart vault setup"))?;
        let text = setup.kit.text();
        let groups: Vec<_> = text.split('-').collect();
        if !groups[3].eq_ignore_ascii_case(group3.trim())
            || !groups[12].eq_ignore_ascii_case(group12.trim())
        {
            return Err(Error::Invalid(
                "recovery kit confirmation did not match; restart setup",
            ));
        }
        if let SetupKind::Rotation(epoch) = setup.kind {
            let mut vault = self.guard();
            let update = vault.prepare_recovery_rotation(setup.password.as_bytes(), &setup.kit)?;
            let access = self.gate.read()?;
            if access.epoch() != epoch {
                return Err(Error::Locked);
            }
            vault.apply_credential_update(update)?;
            self.recovery_available.store(true, Ordering::Release);
            drop(vault);
            drop(access);
            self.notify();
            return Ok(());
        }
        let epoch = self.gate.epoch();
        if self.status().phase != Phase::Legacy {
            return Err(Error::Locked);
        }
        let (params, _) = openward_crypto::password::calibrate()?;
        if self.gate.epoch() != epoch {
            return Err(Error::Locked);
        }
        // Revoke all old async results before replacing the on-disk authority.
        if !self
            .gate
            .close_when(|| self.status().phase == Phase::Legacy)
        {
            return Err(Error::Locked);
        }
        let install_epoch = epoch.checked_add(1).ok_or(Error::Locked)?;
        self.phase(Phase::Changing);
        self.notify();
        let mut vault = self.guard();
        drop(std::mem::replace(&mut *vault, Vault::open_in_memory()?));
        let installed =
            Vault::migrate_with_recovery(&self.path, setup.password.as_bytes(), params, &setup.kit);
        // Release migration's retained process lock before opening the same path.
        let result = installed.map(drop);
        let opened = Vault::open_session(&self.path);
        match opened {
            Ok(v) => *vault = v,
            Err(e) => {
                self.phase(Phase::Locked);
                self.notify();
                return Err(e);
            }
        }
        if let Some(wake) = self
            .vault_wake
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
        {
            vault.on_change(move || wake());
        }
        self.recovery_available
            .store(vault.has_recovery()?, Ordering::Release);
        if !vault.is_encrypted() {
            // A pre-install failure restores the original complete plaintext vault.
            if self.gate.open(install_epoch) {
                self.phase(Phase::Legacy);
            } else {
                self.phase(Phase::LegacyPaused);
            }
            self.notify();
            return result;
        }
        let unlocked = result.and_then(|()| vault.unlock_in_place(setup.password.as_bytes()));
        self.finish_auth(install_epoch, &mut vault, unlocked)
    }
    /// Rotation requires the current password, including on a biometrically
    /// unlocked session. The old kit stays active until confirmation commits.
    pub fn prepare_recovery(&self, password: zeroize::Zeroizing<String>) -> Result<SetupView> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("authentication is already in progress"))?;
        let epoch = self.gate.ticket()?;
        self.guard().verify_password(password.as_bytes())?;
        let kit = openward_crypto::unlock::RecoveryKit::generate()?;
        let text = kit.text();
        let access = self.gate.read()?;
        if access.epoch() != epoch {
            return Err(Error::Locked);
        }
        *self.setup.lock().unwrap_or_else(|e| e.into_inner()) = Some(Setup {
            kind: SetupKind::Rotation(epoch),
            password,
            kit,
        });
        Ok(SetupView {
            kit: text,
            confirm_groups: [3, 12],
        })
    }
    pub fn change_password(
        &self,
        authorization: &[u8],
        use_kit: bool,
        password: &str,
        store: &dyn native::Store,
    ) -> Result<()> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("authentication is already in progress"))?;
        let epoch = self.gate.ticket()?;
        if password.chars().count() < 12 || Self::password_score(password)? < 3 {
            return Err(Error::Invalid(
                "choose a stronger master password (at least 12 characters)",
            ));
        }
        let (params, _) = openward_crypto::password::calibrate()?;
        let mut vault = self.guard();
        let id = vault.native_id().ok().flatten();
        let update =
            vault.prepare_password_change(authorization, use_kit, password.as_bytes(), params)?;
        let access = self.gate.read()?;
        if access.epoch() != epoch {
            return Err(Error::Locked);
        }
        vault.apply_credential_update(update)?;
        self.native_enabled.store(false, Ordering::Release);
        self.recovery_available.store(true, Ordering::Release);
        self.cancel_setup();
        drop(vault);
        drop(access);
        self.notify();
        // The obsolete OS item has no active database wrapper after commit.
        // Failure to remove an orphan cannot make the old factor usable again.
        if let Some(id) = id {
            let _ = store.remove(&id);
        }
        Ok(())
    }
    /// Only the currently prepared kit can be printed. No active kit is exposed
    /// merely because biometrics previously opened the vault.
    pub fn prepared_recovery_qr(&self) -> Result<Vec<u8>> {
        let _access = self.gate.read()?;
        let pending = self.setup.lock().unwrap_or_else(|e| e.into_inner());
        let setup = pending
            .as_ref()
            .ok_or(Error::Invalid("prepare a recovery kit first"))?;
        recovery_document::qr(&setup.kit)
    }
    pub fn export_prepared_recovery(&self, path: &Path) -> Result<()> {
        let epoch = self.gate.ticket()?;
        if path.extension().and_then(|s| s.to_str()) != Some("pdf") {
            return Err(Error::Invalid("choose a new .pdf file"));
        }
        let document = {
            let pending = self.setup.lock().unwrap_or_else(|e| e.into_inner());
            let setup = pending
                .as_ref()
                .ok_or(Error::Invalid("prepare a recovery kit first"))?;
            recovery_document::pdf(&setup.kit)?
        };
        let parent = path.parent().ok_or(Error::Invalid("invalid PDF path"))?;
        let mut file = tempfile::NamedTempFile::new_in(parent)?;
        use std::io::Write;
        file.write_all(&document)?;
        file.as_file().sync_all()?;
        let access = self.gate.read()?;
        if access.epoch() != epoch {
            return Err(Error::Locked);
        }
        // Never overwrite a vault, a symlink, or a previously saved kit.
        file.persist_noclobber(path).map_err(|e| e.error)?;
        Ok(())
    }
    pub fn resume_legacy(&self) -> Result<()> {
        let _busy = self
            .operation
            .try_lock()
            .map_err(|_| Error::Invalid("setup is still in progress"))?;
        if self.status().phase != Phase::LegacyPaused || self.guard().is_encrypted() {
            return Err(Error::Invalid("not a paused plaintext vault"));
        }
        self.gate.open(self.gate.epoch());
        self.phase(Phase::Legacy);
        self.notify();
        Ok(())
    }
    pub fn lock(&self) -> Result<()> {
        self.cancel_setup();
        if self.status().phase == Phase::Legacy {
            self.gate.close_when(|| true);
            self.gate.open(self.gate.epoch());
            return Err(Error::Invalid("encrypt the vault before locking"));
        }
        self.gate.close_when(|| true);
        self.lock_closed()
    }
    fn lock_closed(&self) -> Result<()> {
        self.cancel_setup();
        self.phase(Phase::Locked);
        self.notify();
        let mut v = self.guard();
        if v.is_encrypted() {
            v.lock_in_place()?;
        } else {
            self.phase(Phase::LegacyPaused);
            self.notify();
        }
        Ok(())
    }
    pub fn enforce_idle(&self) -> Result<bool> {
        self.enforce_idle_at(Instant::now())
    }
    fn enforce_idle_at(&self, now: Instant) -> Result<bool> {
        let seconds = self.timeout.load(Ordering::Acquire);
        if seconds == 0 || self.status().phase != Phase::Unlocked {
            return Ok(false);
        }
        if self.gate.close_when(|| {
            now.saturating_duration_since(*self.activity.lock().unwrap_or_else(|e| e.into_inner()))
                >= Duration::from_secs(seconds)
        }) {
            self.lock_closed()?;
            return Ok(true);
        }
        Ok(false)
    }
    pub fn path(&self) -> &Path {
        &self.path
    }
}

fn native_error(error: native::Error) -> Error {
    match error {
        native::Error::Cancelled => Error::Invalid("native authentication cancelled"),
        native::Error::Unavailable => {
            Error::Invalid("native authentication unavailable; use your password")
        }
        native::Error::Missing => Error::Invalid("native unlock key missing; use your password"),
        native::Error::Failed(_) => {
            Error::Invalid("native authentication failed; use your password")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use openward_vault::proto::{Data, Host};
    fn session() -> (tempfile::TempDir, VaultSession) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let mut v = Vault::create_encrypted(
            &path,
            b"public test password",
            openward_crypto::password::KdfParams::new(65536, 1).unwrap(),
        )
        .unwrap();
        v.create(Data::Host(Host {
            label: "private host".into(),
            address: "private.example".into(),
            ..Host::default()
        }))
        .unwrap();
        drop(v);
        (dir, VaultSession::open(&path).unwrap())
    }
    #[test]
    fn locked_at_start_wrong_password_retains_process_lock_and_roundtrips() {
        let (_dir, s) = session();
        assert_eq!(s.status().phase, Phase::Locked);
        assert!(matches!(s.access(), Err(Error::Locked)));
        assert!(s.unlock(b"wrong password").is_err());
        assert!(matches!(
            Vault::open_locked(s.path()),
            Err(Error::OpenElsewhere)
        ));
        s.unlock(b"public test password").unwrap();
        assert_eq!(s.access().unwrap().items().count(), 1);
        s.lock().unwrap();
        assert!(s.gate.ticket().is_err());
        assert!(s.access().is_err());
        s.unlock(b"public test password").unwrap();
        assert_eq!(s.access().unwrap().hosts()[0].1.label, "private host");
    }
    #[test]
    fn initial_security_snapshot_cannot_overtake_a_lock_notification() {
        let (_dir, s) = session();
        let s = Arc::new(s);
        s.unlock(b"public test password").unwrap();
        let (entered, wait) = std::sync::mpsc::channel();
        let (resume, rx) = std::sync::mpsc::channel();
        let rx = Mutex::new(rx);
        let phases = Arc::new(Mutex::new(Vec::new()));
        let initial = AtomicBool::new(true);
        std::thread::scope(|scope| {
            let weak = Arc::downgrade(&s);
            let observed = Arc::clone(&phases);
            let watcher_session = Arc::clone(&s);
            let watcher = scope.spawn(move || {
                watcher_session.watch(Arc::new(move || {
                    let phase = weak.upgrade().unwrap().status().phase;
                    if initial.swap(false, Ordering::AcqRel) {
                        entered.send(()).unwrap();
                        rx.lock().unwrap().recv().unwrap();
                    }
                    observed.lock().unwrap().push(phase);
                }))
            });
            wait.recv_timeout(Duration::from_secs(3)).unwrap();
            let locked = scope.spawn(|| s.lock());
            let deadline = Instant::now() + Duration::from_secs(3);
            while s.status().phase != Phase::Locked {
                assert!(Instant::now() < deadline, "lock did not revoke access");
                std::thread::sleep(Duration::from_millis(1));
            }
            resume.send(()).unwrap();
            watcher.join().unwrap();
            locked.join().unwrap().unwrap();
        });
        assert_eq!(*phases.lock().unwrap(), [Phase::Unlocked, Phase::Locked]);
    }
    #[test]
    fn activity_deadline_and_stale_async_tickets() {
        let (_dir, s) = session();
        s.unlock(b"public test password").unwrap();
        let ticket = s.gate.ticket().unwrap();
        let start = *s.activity.lock().unwrap();
        assert!(!s.enforce_idle_at(start + Duration::from_secs(899)).unwrap());
        assert!(s.enforce_idle_at(start + Duration::from_secs(900)).unwrap());
        s.unlock(b"public test password").unwrap();
        assert!(s.gate.check(ticket).is_err());
        s.set_auto_lock(0).unwrap();
        assert!(
            !s.enforce_idle_at(start + Duration::from_secs(100000))
                .unwrap()
        );
    }
}

#[cfg(test)]
mod factor_tests {
    use super::*;
    use native::{Key, Kind, Store};
    struct FakeStore {
        kind: Kind,
        keys: Mutex<std::collections::HashMap<String, [u8; 32]>>,
        fail: AtomicBool,
    }
    impl FakeStore {
        fn new(kind: Kind) -> Self {
            Self {
                kind,
                keys: Mutex::default(),
                fail: AtomicBool::new(false),
            }
        }
    }
    impl Store for FakeStore {
        fn kind(&self) -> Kind {
            self.kind
        }
        fn create(&self, id: &str) -> std::result::Result<Key, native::Error> {
            self.keys.lock().unwrap().insert(id.into(), [19; 32]);
            Ok(zeroize::Zeroizing::new([19; 32]))
        }
        fn read(&self, id: &str) -> std::result::Result<Key, native::Error> {
            if self.fail.load(Ordering::Acquire) {
                return Err(native::Error::Cancelled);
            }
            self.keys
                .lock()
                .unwrap()
                .get(id)
                .copied()
                .map(zeroize::Zeroizing::new)
                .ok_or(native::Error::Missing)
        }
        fn remove(&self, id: &str) -> std::result::Result<(), native::Error> {
            self.keys.lock().unwrap().remove(id);
            Ok(())
        }
    }
    fn session() -> (tempfile::TempDir, Arc<VaultSession>) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        drop(
            Vault::create_encrypted(
                &path,
                b"public test password",
                openward_crypto::password::KdfParams::new(65536, 1).unwrap(),
            )
            .unwrap(),
        );
        let s = Arc::new(VaultSession::open(&path).unwrap());
        (dir, s)
    }
    #[test]
    fn recovery_confirmation_cancellation_and_password_reauthorization() {
        let (dir, s) = session();
        s.unlock(b"public test password").unwrap();
        assert!(
            s.prepare_recovery(zeroize::Zeroizing::new("wrong".into()))
                .is_err()
        );
        let pending = s
            .prepare_recovery(zeroize::Zeroizing::new("public test password".into()))
            .unwrap();
        let groups: Vec<_> = pending.kit.split('-').collect();
        assert!(!s.prepared_recovery_qr().unwrap().is_empty());
        let pdf = dir.path().join("kit.pdf");
        s.export_prepared_recovery(&pdf).unwrap();
        assert!(std::fs::read(&pdf).unwrap().starts_with(b"%PDF-1.4"));
        assert!(s.export_prepared_recovery(&pdf).is_err());
        s.lock().unwrap();
        assert!(s.complete_setup(groups[3], groups[12]).is_err());
        assert!(s.recover(&pending.kit).is_err());
        s.unlock(b"public test password").unwrap();
        let pending = s
            .prepare_recovery(zeroize::Zeroizing::new("public test password".into()))
            .unwrap();
        let groups: Vec<_> = pending.kit.split('-').collect();
        assert!(s.complete_setup("WRNG", groups[12]).is_err());
        assert!(s.prepared_recovery_qr().is_err());
        let pending = s
            .prepare_recovery(zeroize::Zeroizing::new("public test password".into()))
            .unwrap();
        let groups: Vec<_> = pending.kit.split('-').collect();
        s.complete_setup(groups[3], groups[12]).unwrap();
        let store = FakeStore::new(Kind::TouchId);
        s.enable_native(&store, false).unwrap();
        const NEXT: &str = "Meteor-7-Parchment-Unfurl-Quartz-92!";
        assert!(s.change_password(b"wrong", false, NEXT, &store).is_err());
        assert!(s.status().native_enabled);
        assert!(
            s.change_password(b"public test password", false, "weak", &store)
                .is_err()
        );
        s.change_password(pending.kit.as_bytes(), true, NEXT, &store)
            .unwrap();
        assert!(!s.status().native_enabled);
        assert!(store.keys.lock().unwrap().is_empty());
        s.lock().unwrap();
        assert!(s.unlock(b"public test password").is_err());
        s.recover(&pending.kit).unwrap();
        s.lock().unwrap();
        s.unlock(NEXT.as_bytes()).unwrap();
    }
    #[test]
    fn damaged_optional_factors_leave_password_unlock_and_reenrollment_available() {
        let (dir, s) = session();
        drop(s);
        let path = dir.path().join("vault.db");
        let db = rusqlite::Connection::open(&path).unwrap();
        for name in ["local_native_v1", "local_recovery_v1"] {
            db.execute(
                "INSERT INTO meta VALUES (?1,?2)",
                rusqlite::params![name, vec![0u8; 65536]],
            )
            .unwrap();
        }
        drop(db);
        let s = VaultSession::open(&path).unwrap();
        assert_eq!(s.status().phase, Phase::Locked);
        assert!(!s.status().native_enabled);
        assert!(!s.status().recovery_available);
        assert!(s.access().is_err());
        s.unlock(b"public test password").unwrap();
        let store = FakeStore::new(Kind::TouchId);
        s.enable_native(&store, false).unwrap();
        s.lock().unwrap();
        s.unlock_native(&store).unwrap();
        assert_eq!(s.status().phase, Phase::Unlocked);
    }
    #[test]
    fn native_cancel_and_linux_ack_keep_password_fallback_and_default_off() {
        let (_dir, s) = session();
        let store = FakeStore::new(Kind::SessionKeyring);
        assert!(!s.status().native_enabled);
        s.unlock(b"public test password").unwrap();
        assert!(s.enable_native(&store, false).is_err());
        assert!(store.keys.lock().unwrap().is_empty());
        s.enable_native(&store, true).unwrap();
        assert!(s.status().native_enabled);
        s.lock().unwrap();
        store.fail.store(true, Ordering::Release);
        assert!(s.unlock_native(&store).is_err());
        assert_eq!(s.status().phase, Phase::Locked);
        assert!(s.gate.ticket().is_err());
        s.unlock(b"public test password").unwrap();
        s.lock().unwrap();
        store.fail.store(false, Ordering::Release);
        s.unlock_native(&store).unwrap();
        s.disable_native(&store).unwrap();
        assert!(!s.status().native_enabled);
        assert!(store.keys.lock().unwrap().is_empty());
    }
    struct Paused<'a> {
        inner: &'a FakeStore,
        entered: std::sync::mpsc::Sender<()>,
        resume: Mutex<std::sync::mpsc::Receiver<()>>,
    }
    impl Store for Paused<'_> {
        fn kind(&self) -> Kind {
            Kind::TouchId
        }
        fn create(&self, id: &str) -> std::result::Result<Key, native::Error> {
            self.inner.create(id)
        }
        fn remove(&self, id: &str) -> std::result::Result<(), native::Error> {
            self.inner.remove(id)
        }
        fn read(&self, id: &str) -> std::result::Result<Key, native::Error> {
            self.entered.send(()).unwrap();
            self.resume.lock().unwrap().recv().unwrap();
            self.inner.read(id)
        }
    }
    #[test]
    fn pending_native_auth_cannot_reopen_after_suspend_or_block_the_lock() {
        let (_dir, s) = session();
        let store = FakeStore::new(Kind::TouchId);
        s.unlock(b"public test password").unwrap();
        s.enable_native(&store, false).unwrap();
        s.lock().unwrap();
        let (entered, wait) = std::sync::mpsc::channel();
        let (resume, rx) = std::sync::mpsc::channel();
        let paused = Paused {
            inner: &store,
            entered,
            resume: Mutex::new(rx),
        };
        std::thread::scope(|scope| {
            let handle = scope.spawn(|| s.unlock_native(&paused));
            wait.recv_timeout(Duration::from_secs(3)).unwrap();
            s.lock().unwrap();
            assert!(s.unlock(b"public test password").is_err());
            resume.send(()).unwrap();
            assert!(handle.join().unwrap().is_err());
        });
        assert_eq!(s.status().phase, Phase::Locked);
        assert!(s.access().is_err());
        s.unlock(b"public test password").unwrap();
    }
    #[test]
    fn mandatory_kit_is_installed_atomically_and_timeout_survives_restart() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let s = VaultSession::open(&path).unwrap();
        assert!(
            s.prepare_setup(zeroize::Zeroizing::new("password1234".into()))
                .is_err()
        );
        let setup = s
            .prepare_setup(zeroize::Zeroizing::new(
                "Meteor-7-Parchment-Unfurl-Quartz-92!".into(),
            ))
            .unwrap();
        let kit = setup.kit;
        let groups: Vec<_> = kit.split('-').collect();
        s.complete_setup(groups[3], groups[12]).unwrap();
        assert_eq!(s.status().phase, Phase::Unlocked);
        assert!(s.status().recovery_available);
        s.set_auto_lock(60).unwrap();
        assert!(s.set_auto_lock(86401).is_err());
        s.lock().unwrap();
        s.recover(&kit).unwrap();
        drop(s);
        let s = VaultSession::open(&path).unwrap();
        assert_eq!(s.status().auto_lock_seconds, 60);
        assert_eq!(s.status().phase, Phase::Locked);
        s.recover(&kit).unwrap();
    }
    #[test]
    fn cancelling_setup_erases_the_pending_secret_and_preserves_legacy() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        let s = VaultSession::open(&path).unwrap();
        let setup = s
            .prepare_setup(zeroize::Zeroizing::new(
                "Meteor-7-Parchment-Unfurl-Quartz-92!".into(),
            ))
            .unwrap();
        let groups: Vec<_> = setup.kit.split('-').collect();
        s.cancel_setup();
        assert!(s.complete_setup(groups[3], groups[12]).is_err());
        assert_eq!(s.status().phase, Phase::Legacy);
        assert!(!s.guard().is_encrypted());
    }
}
