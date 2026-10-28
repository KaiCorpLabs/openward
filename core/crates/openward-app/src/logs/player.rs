//! Plays a recording back into a terminal of its own, which the UI draws
//! like any other: forward at a speed, paused, or at any moment.
//!
//! Going back replays from the start without drawing in between: the
//! terminal's state is the sum of everything before.

use std::sync::{Arc, Mutex, MutexGuard, Weak};
use std::thread;
use std::time::{Duration, Instant};

use super::cast::{Event, Recording};
use crate::Terminal;

/// A silence longer than this plays as this long.
const IDLE_LIMIT: f64 = 2.0;
/// How often a playing recording moves on.
const TICK: Duration = Duration::from_millis(16);

pub struct Player {
    term: Arc<Terminal>,
    rec: Recording,
    state: Mutex<State>,
}

struct State {
    /// Seconds from the start.
    pos: f64,
    /// The first event not played yet.
    next: usize,
    playing: bool,
    speed: f64,
    /// A thread is moving it on.
    running: bool,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl Player {
    pub(crate) fn new(rec: Recording, scrollback: usize) -> Arc<Self> {
        let term = Terminal::new(rec.header.width, rec.header.height, scrollback);
        Arc::new(Self {
            term,
            rec,
            state: Mutex::new(State {
                pos: 0.0,
                next: 0,
                playing: false,
                speed: 1.0,
                running: false,
            }),
        })
    }

    /// What it plays into: draw it, never type into it.
    pub fn terminal(&self) -> Arc<Terminal> {
        Arc::clone(&self.term)
    }

    pub fn duration(&self) -> f64 {
        self.rec.duration()
    }

    /// False when the recording stops short (the app closed suddenly).
    pub fn complete(&self) -> bool {
        self.rec.complete
    }

    /// The markers, `(seconds, label)`: commands (`$ …`) and OpenWard's
    /// own ([`super::cast::Mark`]).
    pub fn markers(&self) -> Vec<(f64, String)> {
        self.rec
            .events
            .iter()
            .filter_map(|(t, e)| match e {
                Event::Marker(label) => Some((*t, label.clone())),
                _ => None,
            })
            .collect()
    }

    pub fn position(&self) -> f64 {
        lock(&self.state).pos
    }

    pub fn playing(&self) -> bool {
        lock(&self.state).playing
    }

    /// Shows the screen as it was at `t` seconds.
    pub fn seek(&self, t: f64) {
        let mut s = lock(&self.state);
        self.seek_in(&mut s, t);
    }

    fn seek_in(&self, s: &mut State, t: f64) {
        let t = t.clamp(0.0, self.duration());
        if t < s.pos || (s.next > 0 && self.rec.events[s.next - 1].0 > t) {
            let (cols, rows) = (self.rec.header.width, self.rec.header.height);
            self.term.reset(cols, rows);
            s.next = 0;
        }
        self.advance(s, t);
    }

    /// Plays the events up to `t`.
    fn advance(&self, s: &mut State, t: f64) {
        while let Some((at, event)) = self.rec.events.get(s.next) {
            if *at > t {
                break;
            }
            match event {
                Event::Output(text) => self.term.feed(text.as_bytes()),
                Event::Resize(cols, rows) => self.term.resize(*cols, *rows),
                Event::Marker(_) => {}
            }
            s.next += 1;
        }
        s.pos = t;
    }

    /// Plays on from where it is (from the start, if it was at the end),
    /// `speed` times as fast.
    pub fn play(self: &Arc<Self>, speed: f64) {
        let mut s = lock(&self.state);
        if s.next >= self.rec.events.len() {
            self.seek_in(&mut s, 0.0);
        }
        s.speed = speed.clamp(0.1, 64.0);
        s.playing = true;
        if !s.running {
            s.running = true;
            let me = Arc::downgrade(self);
            let started = thread::Builder::new()
                .name("openward-player".into())
                .spawn(move || run(&me));
            if started.is_err() {
                s.running = false;
                s.playing = false;
            }
        }
    }

    pub fn pause(&self) {
        lock(&self.state).playing = false;
    }

    /// One step of playing: false when it stopped.
    fn tick(&self, real: f64) -> bool {
        let mut s = lock(&self.state);
        if !s.playing {
            s.running = false;
            return false;
        }
        if let Some((at, _)) = self.rec.events.get(s.next)
            && at - s.pos > IDLE_LIMIT
        {
            s.pos = at - IDLE_LIMIT;
        }
        let target = s.pos + real * s.speed;
        self.advance(&mut s, target);
        if s.next >= self.rec.events.len() {
            s.pos = self.duration();
            s.playing = false;
            s.running = false;
            return false;
        }
        true
    }
}

fn run(player: &Weak<Player>) {
    let mut last = Instant::now();
    loop {
        thread::sleep(TICK);
        let real = last.elapsed().as_secs_f64();
        last = Instant::now();
        // Gone with its last handle.
        let Some(player) = player.upgrade() else {
            return;
        };
        if !player.tick(real) {
            return;
        }
    }
}
