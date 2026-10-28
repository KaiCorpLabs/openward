//! Follows a connection's events to keep its session log: the entry
//! begins when the shell is up, the recording notes the cuts and the
//! comebacks, and both end with the session.

use std::sync::{Arc, Mutex, MutexGuard, Weak};

use super::cast::Mark;
use super::{Begin, End, Logs, Session};
use crate::Terminal;
use crate::events::{Event, EventSink, Persistence};

pub(crate) struct LogSink {
    inner: Arc<dyn EventSink>,
    logs: Arc<Logs>,
    term: Weak<Terminal>,
    state: Mutex<State>,
}

struct State {
    /// What the entry will be, until it begins.
    begin: Option<Begin>,
    session: Option<Arc<Session>>,
    /// The connection went away and is being tried again.
    lost: bool,
    tmux: bool,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl LogSink {
    pub(crate) fn new(
        inner: Arc<dyn EventSink>,
        logs: &Arc<Logs>,
        term: &Arc<Terminal>,
        begin: Begin,
    ) -> Arc<Self> {
        Arc::new(Self {
            inner,
            logs: Arc::clone(logs),
            term: Arc::downgrade(term),
            state: Mutex::new(State {
                begin: Some(begin),
                session: None,
                lost: false,
                tmux: false,
            }),
        })
    }

    fn follow(&self, event: &Event) {
        let mut s = lock(&self.state);
        match event {
            Event::Persistent { state, .. } => {
                s.tmux = matches!(state, Persistence::New | Persistence::Resumed);
                if let Some(session) = &s.session {
                    session.set_tmux(s.tmux);
                }
            }
            Event::Connected(_) | Event::Started { .. } => {
                if let Some(session) = &s.session {
                    if s.lost {
                        session.mark(Mark::Back);
                        s.lost = false;
                    }
                    return;
                }
                let (Some(mut begin), Some(term)) = (s.begin.take(), self.term.upgrade()) else {
                    return;
                };
                let size = term.size();
                (begin.cols, begin.rows, begin.tmux) = (size.cols, size.rows, s.tmux);
                // If the recording cannot start, the entry alone.
                let session = self.logs.begin(begin.clone()).or_else(|_| {
                    begin.record = false;
                    self.logs.begin(begin)
                });
                if let Ok(session) = session {
                    term.attach_log(Arc::clone(&session));
                    s.session = Some(session);
                }
            }
            Event::Reconnecting { .. } => {
                if let Some(session) = &s.session
                    && !s.lost
                {
                    session.mark(Mark::Lost);
                    s.lost = true;
                }
            }
            Event::Closed { failure, .. } => {
                if let Some(session) = s.session.take() {
                    if let Some(term) = self.term.upgrade() {
                        term.release_log(&session);
                    }
                    session.finish(if failure.is_some() {
                        End::Lost
                    } else {
                        End::Closed
                    });
                }
            }
            _ => {}
        }
    }
}

impl EventSink for LogSink {
    fn send(&self, event: Event) {
        self.follow(&event);
        self.inner.send(event);
    }
}
