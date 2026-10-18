//! Whether a connection is still there. A server that goes away without
//! closing (a reboot, a network that drops) says nothing: the connection
//! looks open on this side until something checks. This asks the server
//! every so often, and at once when typing brings nothing back; it says
//! when the server stops answering, and returns when it is gone.

use std::future::Future;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use tokio::time::Instant;

use crate::events::Health;

/// When to ask and when to give up, from the host's keepalive.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Timing {
    /// Between questions.
    pub every: Duration,
    /// Unanswered this long: it does not respond.
    pub stalled_after: Duration,
    /// Unanswered this long: it is gone.
    pub lost_after: Duration,
    /// Typing that brings nothing back for this long asks at once.
    pub after_typing: Duration,
}

impl Timing {
    /// From the keepalive (10 s by default): asked every keepalive, "does
    /// not respond" after 5 s, gone after two keepalives (20 s) and never
    /// less than 15 s. None, with keepalives off: nothing is checked.
    pub fn from_keepalive(every: Option<Duration>) -> Option<Self> {
        let every = every.filter(|e| !e.is_zero())?;
        Some(Self {
            every,
            stalled_after: Duration::from_secs(5).min(every),
            lost_after: (every * 2).max(Duration::from_secs(15)),
            after_typing: Duration::from_secs(2),
        })
    }
}

/// When a terminal last sent input and last got output, to tell typing
/// that brings no answer.
#[derive(Debug)]
pub struct Activity {
    base: Instant,
    /// Milliseconds after `base`, plus one; 0 is never.
    input: AtomicU64,
    output: AtomicU64,
}

impl Default for Activity {
    fn default() -> Self {
        Self {
            base: Instant::now(),
            input: AtomicU64::new(0),
            output: AtomicU64::new(0),
        }
    }
}

impl Activity {
    fn stamp(&self, at: &AtomicU64) {
        let ms = Instant::now()
            .saturating_duration_since(self.base)
            .as_millis() as u64;
        at.store(ms + 1, Ordering::Relaxed);
    }

    fn get(&self, at: &AtomicU64) -> Option<Instant> {
        match at.load(Ordering::Relaxed) {
            0 => None,
            ms => Some(self.base + Duration::from_millis(ms - 1)),
        }
    }

    pub fn sent(&self) {
        self.stamp(&self.input);
    }

    pub fn received(&self) {
        self.stamp(&self.output);
    }

    fn last_output(&self) -> Option<Instant> {
        self.get(&self.output)
    }

    /// Input sent at least `after` ago that no output followed: when.
    fn unanswered_input(&self, now: Instant, after: Duration) -> Option<Instant> {
        let input = self.get(&self.input)?;
        let answered = self.last_output().is_some_and(|o| o >= input);
        (!answered && now.saturating_duration_since(input) >= after).then_some(input)
    }
}

const TICK: Duration = Duration::from_millis(250);

/// Watches a connection with `ping` (true when the server answered, false
/// when the connection is gone) until it stops answering for good: returns
/// for how long it went unanswered. Output in `activity` counts as an
/// answer; input that none follows asks at once. `report` hears each
/// answer and the moment it stops answering.
pub(crate) async fn watch<P, F>(
    ping: P,
    activity: Option<&Activity>,
    timing: Timing,
    mut report: impl FnMut(Health),
) -> Duration
where
    P: Fn() -> F,
    F: Future<Output = bool>,
{
    let mut last_asked = Instant::now();
    // The input that last made it ask, so that it asks once for it.
    let mut asked_for: Option<Instant> = None;
    loop {
        loop {
            tokio::time::sleep(TICK).await;
            let now = Instant::now();
            if now.saturating_duration_since(last_asked) >= timing.every {
                break;
            }
            let typed = activity.and_then(|a| a.unanswered_input(now, timing.after_typing));
            if typed.is_some() && typed != asked_for {
                asked_for = typed;
                break;
            }
        }
        let sent = Instant::now();
        last_asked = sent;
        let answer = ping();
        tokio::pin!(answer);
        let mut stalled = false;
        loop {
            tokio::select! {
                alive = &mut answer => {
                    if !alive {
                        return Instant::now().saturating_duration_since(sent);
                    }
                    let rtt = Instant::now().saturating_duration_since(sent);
                    report(Health::Answered {
                        rtt_ms: Some(rtt.as_millis().min(u128::from(u32::MAX)) as u32),
                    });
                    break;
                }
                () = tokio::time::sleep(TICK) => {
                    let now = Instant::now();
                    // Output after the question shows the server is there.
                    let heard = activity
                        .and_then(Activity::last_output)
                        .filter(|o| *o > sent)
                        .map_or(sent, |o| o.max(sent));
                    let silent = now.saturating_duration_since(heard);
                    if silent >= timing.lost_after {
                        return silent;
                    }
                    if !stalled && silent >= timing.stalled_after {
                        stalled = true;
                        report(Health::Stalled {
                            silent_ms: silent.as_millis() as u64,
                        });
                    } else if stalled && silent < timing.stalled_after {
                        stalled = false;
                        report(Health::Answered { rtt_ms: None });
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use super::*;

    fn timing() -> Timing {
        Timing::from_keepalive(Some(Duration::from_secs(10))).unwrap()
    }

    #[test]
    fn timings_follow_the_keepalive() {
        let t = timing();
        assert_eq!(
            (t.every, t.stalled_after, t.lost_after),
            (
                Duration::from_secs(10),
                Duration::from_secs(5),
                Duration::from_secs(20)
            )
        );
        let slow = Timing::from_keepalive(Some(Duration::from_secs(30))).unwrap();
        assert_eq!(slow.lost_after, Duration::from_secs(60));
        let fast = Timing::from_keepalive(Some(Duration::from_secs(2))).unwrap();
        assert_eq!(
            (fast.stalled_after, fast.lost_after),
            (Duration::from_secs(2), Duration::from_secs(15))
        );
        assert_eq!(Timing::from_keepalive(None), None);
        assert_eq!(Timing::from_keepalive(Some(Duration::ZERO)), None);
    }

    /// A server that answers after `delay`, or never once `gone_at` has
    /// passed; counting the questions.
    struct Server {
        start: Instant,
        delay: Duration,
        gone_at: Option<Duration>,
        asked: Mutex<Vec<Duration>>,
    }

    impl Server {
        fn new(delay: Duration, gone_at: Option<Duration>) -> Arc<Self> {
            Arc::new(Self {
                start: Instant::now(),
                delay,
                gone_at,
                asked: Mutex::new(Vec::new()),
            })
        }

        fn ping(self: &Arc<Self>) -> impl Future<Output = bool> + use<> {
            let me = Arc::clone(self);
            async move {
                let at = Instant::now() - me.start;
                me.asked.lock().unwrap().push(at);
                if me.gone_at.is_some_and(|g| at >= g) {
                    std::future::pending::<()>().await;
                }
                tokio::time::sleep(me.delay).await;
                true
            }
        }
    }

    fn secs(d: Duration) -> u64 {
        d.as_secs()
    }

    #[tokio::test(start_paused = true)]
    async fn a_server_that_goes_away_is_noticed_in_seconds() {
        let server = Server::new(Duration::from_millis(30), Some(Duration::from_secs(25)));
        let reports = Mutex::new(Vec::new());
        let start = Instant::now();
        let silent = watch(
            || server.ping(),
            None,
            timing(),
            |h| {
                reports
                    .lock()
                    .unwrap()
                    .push((secs(Instant::now() - start), h))
            },
        )
        .await;
        // Asked at 10 and 20 s (answered), then at 30 s: no answer.
        assert_eq!(
            server
                .asked
                .lock()
                .unwrap()
                .iter()
                .map(|d| secs(*d))
                .collect::<Vec<_>>(),
            [10, 20, 30]
        );
        assert_eq!(secs(silent), 20);
        assert_eq!(secs(Instant::now() - start), 50);
        let reports = reports.into_inner().unwrap();
        assert_eq!(reports[0], (10, Health::Answered { rtt_ms: Some(30) }));
        assert_eq!(reports[2], (35, Health::Stalled { silent_ms: 5000 }));
        assert_eq!(reports.len(), 3);
    }

    #[tokio::test(start_paused = true)]
    async fn a_slow_answer_stalls_and_comes_back() {
        let server = Server::new(Duration::from_secs(8), None);
        let reports = Mutex::new(Vec::new());
        let watching = watch(
            || server.ping(),
            None,
            timing(),
            |h| reports.lock().unwrap().push(h),
        );
        let _ = tokio::time::timeout(Duration::from_secs(19), watching).await;
        assert_eq!(
            reports.into_inner().unwrap(),
            [
                Health::Stalled { silent_ms: 5000 },
                Health::Answered { rtt_ms: Some(8000) }
            ]
        );
    }

    #[tokio::test(start_paused = true)]
    async fn typing_that_brings_nothing_back_asks_at_once() {
        let server = Server::new(Duration::from_millis(10), None);
        let activity = Activity::default();
        let watching = watch(|| server.ping(), Some(&activity), timing(), |_| {});
        let typing = async {
            tokio::time::sleep(Duration::from_secs(3)).await;
            activity.sent();
            // Echoed: no question for it.
            tokio::time::sleep(Duration::from_millis(50)).await;
            activity.received();
            tokio::time::sleep(Duration::from_secs(2)).await;
            // Not echoed.
            activity.sent();
            tokio::time::sleep(Duration::from_secs(4)).await;
        };
        tokio::select! {
            _ = watching => panic!("a server that answers is not lost"),
            () = typing => {}
        }
        // 2 s after the unanswered key (at 5.05 s), on the next tick: before
        // the one at 10 s.
        let asked: Vec<u128> = server
            .asked
            .lock()
            .unwrap()
            .iter()
            .map(|d| d.as_millis() / 250 * 250)
            .collect();
        assert_eq!(asked, [7250]);
    }

    #[tokio::test(start_paused = true)]
    async fn output_counts_as_an_answer() {
        // Its answers are stuck behind a lot of output: still there.
        let server = Server::new(Duration::from_secs(12), None);
        let activity = Activity::default();
        let reports = Mutex::new(Vec::new());
        let watching = watch(
            || server.ping(),
            Some(&activity),
            timing(),
            |h| reports.lock().unwrap().push(h),
        );
        let output = async {
            for _ in 0..80 {
                tokio::time::sleep(Duration::from_millis(500)).await;
                activity.received();
            }
        };
        tokio::select! {
            _ = watching => panic!("output means it is there"),
            () = output => {}
        }
        assert!(
            !reports
                .into_inner()
                .unwrap()
                .iter()
                .any(|h| matches!(h, Health::Stalled { .. }))
        );
    }

    #[tokio::test(start_paused = true)]
    async fn a_closed_connection_returns_at_once() {
        let start = Instant::now();
        watch(|| async { false }, None, timing(), |_| {}).await;
        assert_eq!(secs(Instant::now() - start), 10);
    }
}
