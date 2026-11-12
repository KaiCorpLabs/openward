//! Only public state leaves Rust. Entered passwords move into a zeroizing
//! buffer; native factors and derived/account/vault keys never enter Dart.
use super::{app::OpenWard, vault::VaultError};
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use openward_app::security::{Phase, Status};
use zeroize::Zeroizing;

/// `critical` is only for short synchronous UI reads/input enqueues. Blocking
/// I/O uses an epoch ticket so it cannot keep auto-lock waiting for a device.
#[frb(ignore)]
pub(crate) fn access<T>(
    gate: &openward_app::security::AccessGate,
    critical: bool,
    operation: impl FnOnce() -> T,
) -> openward_app::vault::Result<T> {
    if critical {
        let _permission = gate.read()?;
        Ok(operation())
    } else {
        let ticket = gate.ticket()?;
        let result = operation();
        gate.check(ticket)?;
        Ok(result)
    }
}
#[frb(ignore)]
pub(crate) async fn async_access<T>(
    gate: &openward_app::security::AccessGate,
    operation: impl std::future::Future<Output = T>,
) -> openward_app::vault::Result<T> {
    let ticket = gate.ticket()?;
    let result = operation.await;
    gate.check(ticket)?;
    Ok(result)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VaultPhase {
    Legacy,
    Locked,
    Unlocked,
    Changing,
    LegacyPaused,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SecurityView {
    pub phase: VaultPhase,
    pub auto_lock_seconds: u64,
    pub native_enabled: bool,
    pub recovery_available: bool,
}
impl From<Status> for SecurityView {
    fn from(s: Status) -> Self {
        Self {
            phase: match s.phase {
                Phase::Legacy => VaultPhase::Legacy,
                Phase::Locked => VaultPhase::Locked,
                Phase::Unlocked => VaultPhase::Unlocked,
                Phase::Changing => VaultPhase::Changing,
                Phase::LegacyPaused => VaultPhase::LegacyPaused,
            },
            auto_lock_seconds: s.auto_lock_seconds,
            native_enabled: s.native_enabled,
            recovery_available: s.recovery_available,
        }
    }
}
impl OpenWard {
    #[frb(sync)]
    pub fn security_state(&self) -> SecurityView {
        self.app.security().status().into()
    }
    pub fn watch_security(&self, sink: StreamSink<SecurityView>) {
        let weak = std::sync::Arc::downgrade(self.app.security());
        self.app.security().watch(std::sync::Arc::new(move || {
            if let Some(security) = weak.upgrade() {
                let _ = sink.add(security.status().into());
            }
        }));
    }
    pub fn lock_vault(&self) -> Result<(), VaultError> {
        Ok(self.app.lock_vault()?)
    }
    pub fn unlock_vault(&self, password: String) -> Result<(), VaultError> {
        let password = Zeroizing::new(password);
        Ok(self.app.security().unlock(password.as_bytes())?)
    }
    #[frb(sync)]
    pub fn security_activity(&self) {
        self.app.security().activity();
    }
    pub fn set_auto_lock(&self, seconds: u64) -> Result<(), VaultError> {
        Ok(self.app.security().set_auto_lock(seconds)?)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeProtection {
    TouchId,
    WindowsHello,
    SessionKeyring,
    Unsupported,
}
impl OpenWard {
    #[frb(sync)]
    pub fn native_protection(&self) -> NativeProtection {
        use openward_app::security::native::Kind;
        match openward_app::security::native::kind() {
            Kind::TouchId => NativeProtection::TouchId,
            Kind::WindowsHello => NativeProtection::WindowsHello,
            Kind::SessionKeyring => NativeProtection::SessionKeyring,
            Kind::Unsupported => NativeProtection::Unsupported,
        }
    }
    pub fn unlock_native(&self) -> Result<(), VaultError> {
        Ok(self
            .app
            .security()
            .unlock_native(&openward_app::security::native::System)?)
    }
    pub fn enable_native(&self, linux_ack: bool) -> Result<(), VaultError> {
        Ok(self
            .app
            .security()
            .enable_native(&openward_app::security::native::System, linux_ack)?)
    }
    pub fn disable_native(&self) -> Result<(), VaultError> {
        Ok(self
            .app
            .security()
            .disable_native(&openward_app::security::native::System)?)
    }
    pub fn recover_vault(&self, kit: String) -> Result<(), VaultError> {
        let kit = Zeroizing::new(kit);
        Ok(self.app.security().recover(&kit)?)
    }
    pub fn password_score(&self, password: String) -> Result<u8, VaultError> {
        let password = Zeroizing::new(password);
        Ok(openward_app::security::VaultSession::password_score(
            &password,
        )?)
    }
    pub fn prepare_vault(&self, password: String) -> Result<String, VaultError> {
        let setup = self
            .app
            .security()
            .prepare_setup(Zeroizing::new(password))?;
        Ok(setup.kit.to_string())
    }
    pub fn cancel_vault_setup(&self) {
        self.app.security().cancel_setup();
    }
    pub fn complete_vault_setup(&self, group3: String, group12: String) -> Result<(), VaultError> {
        let group3 = Zeroizing::new(group3);
        let group12 = Zeroizing::new(group12);
        Ok(self.app.security().complete_setup(&group3, &group12)?)
    }
    pub fn resume_legacy_vault(&self) -> Result<(), VaultError> {
        Ok(self.app.security().resume_legacy()?)
    }
}

#[cfg(all(test, unix))]
mod tests {
    use std::{
        sync::Arc,
        time::{Duration, Instant},
    };
    struct Sink;
    impl openward_app::events::EventSink for Sink {
        fn send(&self, _: openward_app::events::Event) {}
    }
    #[test]
    fn locking_redacts_ffi_and_blocks_input_while_the_real_pty_stays_alive() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("vault.db");
        drop(
            openward_app::vault::Vault::create_encrypted(
                &path,
                b"public test password",
                openward_crypto::password::KdfParams::new(65536, 1).unwrap(),
            )
            .unwrap(),
        );
        let local = openward_app::Local {
            home: dir.path().into(),
            user: "test".into(),
            ssh_dir: dir.path().join("ssh"),
            system_ssh_dir: dir.path().join("system-ssh"),
            agent: None,
        };
        let app = Arc::new(openward_app::App::open_as(dir.path(), local).unwrap());
        app.security().unlock(b"public test password").unwrap();
        let term = app.terminal(80, 24, 100);
        app.open_local(&term, Some("/bin/cat".into()), Arc::new(Sink))
            .unwrap();
        let ui = super::super::session::TerminalSession {
            term: Arc::clone(&term),
            access: app.security().gate(),
        };
        fn wait_for(ui: &super::super::session::TerminalSession, needle: &str) {
            let until = Instant::now() + Duration::from_secs(5);
            while !ui.screen_text().contains(needle) {
                assert!(
                    Instant::now() < until,
                    "PTY did not produce expected test output"
                );
                std::thread::sleep(Duration::from_millis(10));
            }
        }
        ui.text("before-lock\r".into());
        wait_for(&ui, "before-lock");
        app.lock_vault().unwrap();
        assert!(ui.screen_text().is_empty());
        assert!(ui.poll().is_none());
        assert!(ui.poll_meta().title.is_empty());
        assert!(ui.selection_text().is_none());
        ui.text("forbidden-ui-input\r".into());
        assert!(!ui.paste("forbidden-paste".into(), false));
        // Trusted background output continues. This bypass is deliberately in
        // the test's Rust core; UI handles always go through the access gate.
        term.text("background-still-alive\r");
        app.security().unlock(b"public test password").unwrap();
        wait_for(&ui, "background-still-alive");
        assert!(!ui.screen_text().contains("forbidden-ui-input"));
        assert!(!ui.screen_text().contains("forbidden-paste"));
        ui.text("after-unlock\r".into());
        wait_for(&ui, "after-unlock");
        ui.close();
    }
}
