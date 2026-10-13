//! Terminal session for the render harness.
//!
//! A background thread feeds a synthetic workload into the engine at a given
//! rate; the UI pulls damage frames once per vsync with [`TermSession::encode`].
//! Each frame carries the time its oldest input byte arrived, on the clock
//! exposed by [`now_micros`], so Dart can measure input-to-paint latency.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use flutter_rust_bridge::frb;
use ghostty_engine::GhosttyEngine;
use openward_term::alacritty::AlacrittyEngine;
use openward_term::{FrameEncoder, Size, TermEngine};
use s1_corpus::Workload;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    let _ = epoch();
}

fn epoch() -> Instant {
    static EPOCH: OnceLock<Instant> = OnceLock::new();
    *EPOCH.get_or_init(Instant::now)
}

fn now() -> u64 {
    epoch().elapsed().as_micros() as u64
}

/// Monotonic microseconds shared by Rust and Dart for latency measurements.
#[frb(sync)]
pub fn now_micros() -> u64 {
    now()
}

#[frb(sync)]
pub fn workload_names() -> Vec<String> {
    Workload::ALL.iter().map(|w| w.name().to_owned()).collect()
}

#[frb(sync)]
pub fn engine_names() -> Vec<String> {
    vec!["alacritty".to_owned(), "ghostty".to_owned()]
}

/// One pull of damage from the engine.
pub struct FrameBatch {
    /// Damage frame v1 (`openward-term` frame.rs).
    pub frame: Vec<u8>,
    /// When the oldest input reflected in this frame was fed (`now_micros`
    /// clock); 0 when the frame carries no new input.
    pub oldest_input_micros: u64,
    /// Total bytes fed since the session started.
    pub fed_bytes: u64,
    pub encode_micros: u32,
    pub workload_running: bool,
}

struct State {
    engine: Box<dyn TermEngine>,
    enc: FrameEncoder,
    oldest_unpainted: Option<u64>,
}

impl State {
    fn feed(&mut self, data: &[u8]) {
        if self.oldest_unpainted.is_none() {
            self.oldest_unpainted = Some(now());
        }
        self.engine.feed(data);
        // Replies to queries (DSR, DA) would go back to the host; there is none.
        self.engine.take_host_writes();
    }
}

#[frb(opaque)]
pub struct TermSession {
    state: Arc<Mutex<State>>,
    fed: Arc<AtomicU64>,
    running: Arc<AtomicBool>,
}

pub fn create_session(
    engine: String,
    cols: u16,
    rows: u16,
    scrollback: u32,
) -> anyhow::Result<TermSession> {
    let size = Size::new(cols, rows);
    let engine: Box<dyn TermEngine> = match engine.as_str() {
        "alacritty" => Box::new(AlacrittyEngine::new(size, scrollback as usize)),
        "ghostty" => Box::new(GhosttyEngine::new(size, scrollback as usize)),
        other => anyhow::bail!("engine not available in this build: {other}"),
    };
    Ok(TermSession {
        state: Arc::new(Mutex::new(State {
            engine,
            enc: FrameEncoder::new(),
            oldest_unpainted: None,
        })),
        fed: Arc::new(AtomicU64::new(0)),
        running: Arc::new(AtomicBool::new(false)),
    })
}

fn lock(state: &Mutex<State>) -> MutexGuard<'_, State> {
    state.lock().unwrap_or_else(|e| e.into_inner())
}

impl TermSession {
    /// Feed bytes directly (keyboard echo tests, pasted text).
    pub fn feed(&self, data: Vec<u8>) {
        lock(&self.state).feed(&data);
        self.fed.fetch_add(data.len() as u64, Ordering::Relaxed);
    }

    /// Encode everything that changed since the previous call, on a worker
    /// thread. The result reaches Dart after the current frame has started,
    /// so it is painted one refresh later ("async" pipeline).
    pub fn encode(&self) -> FrameBatch {
        self.encode_now()
    }

    /// Same as [`encode`](Self::encode) but on the calling (UI) thread, so a
    /// frame can encode, record and paint within one refresh ("sync"
    /// pipeline). Encoding takes tens of microseconds.
    #[frb(sync)]
    pub fn encode_now(&self) -> FrameBatch {
        let mut state = lock(&self.state);
        let started = Instant::now();
        let State {
            engine,
            enc,
            oldest_unpainted,
        } = &mut *state;
        engine.encode_damage(enc);
        let encode_micros = started.elapsed().as_micros() as u32;
        FrameBatch {
            frame: enc.bytes().to_vec(),
            oldest_input_micros: oldest_unpainted.take().unwrap_or(0),
            fed_bytes: self.fed.load(Ordering::Relaxed),
            encode_micros,
            workload_running: self.running.load(Ordering::Relaxed),
        }
    }

    pub fn resize(&self, cols: u16, rows: u16) {
        lock(&self.state).engine.resize(Size::new(cols, rows));
    }

    pub fn scroll(&self, delta_lines: i32) {
        lock(&self.state).engine.scroll_display(delta_lines);
    }

    #[frb(sync)]
    pub fn screen_text(&self) -> String {
        lock(&self.state).engine.screen_text()
    }

    /// Feed `workload` from a background thread at `mib_per_sec` (0 = as
    /// fast as possible) until `total_mib` have been fed or
    /// [`stop_workload`](Self::stop_workload) is called.
    pub fn start_workload(
        &self,
        workload: String,
        cols: u16,
        rows: u16,
        mib_per_sec: f64,
        total_mib: f64,
    ) -> anyhow::Result<()> {
        let workload = Workload::from_name(&workload)
            .ok_or_else(|| anyhow::anyhow!("unknown workload {workload}"))?;
        if self.running.swap(true, Ordering::SeqCst) {
            anyhow::bail!("a workload is already running");
        }
        let total = (total_mib.max(0.0) * 1_048_576.0) as u64;
        let rate = mib_per_sec.max(0.0) * 1_048_576.0;
        // Generate up to 16 MiB once and loop over it for longer runs.
        let data = workload.generate(
            total.min(16 * 1_048_576) as usize,
            usize::from(cols),
            usize::from(rows),
        );
        let state = Arc::clone(&self.state);
        let fed = Arc::clone(&self.fed);
        let running = Arc::clone(&self.running);
        thread::Builder::new()
            .name("s1-workload".into())
            .spawn(move || {
                const CHUNK: usize = 4096;
                let started = Instant::now();
                let mut sent = 0u64;
                'outer: while running.load(Ordering::Relaxed) {
                    for chunk in data.as_bytes().chunks(CHUNK) {
                        if !running.load(Ordering::Relaxed) || sent >= total {
                            break 'outer;
                        }
                        lock(&state).feed(chunk);
                        sent += chunk.len() as u64;
                        fed.fetch_add(chunk.len() as u64, Ordering::Relaxed);
                        if rate > 0.0 {
                            let due = Duration::from_secs_f64(sent as f64 / rate);
                            if let Some(wait) = due.checked_sub(started.elapsed()) {
                                thread::sleep(wait);
                            }
                        } else {
                            // Let the UI thread grab the lock between chunks.
                            thread::yield_now();
                        }
                    }
                }
                running.store(false, Ordering::SeqCst);
            })?;
        Ok(())
    }

    /// Simulates typing into a busy screen: one printable byte at a time
    /// (what a remote shell echoes for one keystroke) at random intervals
    /// between `min_ms` and `max_ms`, for `seconds`. Each frame then carries
    /// at most one keystroke, so its latency is the echo latency.
    pub fn start_typing(&self, seconds: f64, min_ms: u32, max_ms: u32) -> anyhow::Result<()> {
        if self.running.swap(true, Ordering::SeqCst) {
            anyhow::bail!("a workload is already running");
        }
        {
            // Fill the screen first, without timestamps: only keystrokes count.
            let mut state = lock(&self.state);
            let size = state.engine.size();
            let prefill = Workload::SgrLog.generate(
                64 * 1024,
                usize::from(size.cols),
                usize::from(size.rows),
            );
            state.engine.feed(prefill.as_bytes());
            state.engine.feed(b"\x1b[0m\r\n$ ");
            state.engine.take_host_writes();
        }
        let (min_ms, max_ms) = (min_ms.min(max_ms), max_ms.max(min_ms));
        let state = Arc::clone(&self.state);
        let fed = Arc::clone(&self.fed);
        let running = Arc::clone(&self.running);
        thread::Builder::new()
            .name("s1-typing".into())
            .spawn(move || {
                const TEXT: &[u8] =
                    b"ssh deploy@build-01 && tail -f /var/log/app.log | grep -i error ";
                let deadline = Instant::now() + Duration::from_secs_f64(seconds.max(0.0));
                let mut rng = 0x2545_f491_4f6c_dd1d_u64;
                let mut typed = 0usize;
                while running.load(Ordering::Relaxed) && Instant::now() < deadline {
                    // xorshift64: deterministic intervals across runs.
                    rng ^= rng << 13;
                    rng ^= rng >> 7;
                    rng ^= rng << 17;
                    let span = u64::from(max_ms - min_ms) + 1;
                    thread::sleep(Duration::from_millis(u64::from(min_ms) + rng % span));
                    let keystroke: &[u8] = if typed % 60 == 59 {
                        b"\r\n$ "
                    } else {
                        std::slice::from_ref(&TEXT[typed % TEXT.len()])
                    };
                    lock(&state).feed(keystroke);
                    fed.fetch_add(keystroke.len() as u64, Ordering::Relaxed);
                    typed += 1;
                }
                running.store(false, Ordering::SeqCst);
            })?;
        Ok(())
    }

    #[frb(sync)]
    pub fn stop_workload(&self) {
        self.running.store(false, Ordering::SeqCst);
    }
}
