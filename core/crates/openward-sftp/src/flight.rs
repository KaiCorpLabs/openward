//! Several requests on their way from one task.

use std::future::Future;
use std::pin::Pin;
use std::task::Poll;

/// Futures polled together on the task that holds them, each in turn: when
/// it stops (a job paused or cancelled), they stop with it.
pub(crate) struct InFlight<'a, T> {
    futures: Vec<Pin<Box<dyn Future<Output = T> + Send + 'a>>>,
}

impl<T> Default for InFlight<'_, T> {
    fn default() -> Self {
        Self {
            futures: Vec::new(),
        }
    }
}

impl<'a, T> InFlight<'a, T> {
    pub(crate) fn len(&self) -> usize {
        self.futures.len()
    }

    pub(crate) fn push(&mut self, future: impl Future<Output = T> + Send + 'a) {
        self.futures.push(Box::pin(future));
    }

    /// What the next one to finish gives; `None` when there are none.
    pub(crate) async fn next(&mut self) -> Option<T> {
        if self.futures.is_empty() {
            return None;
        }
        std::future::poll_fn(|cx| {
            for k in 0..self.futures.len() {
                if let Poll::Ready(out) = self.futures[k].as_mut().poll(cx) {
                    drop(self.futures.swap_remove(k));
                    return Poll::Ready(Some(out));
                }
            }
            Poll::Pending
        })
        .await
    }
}
