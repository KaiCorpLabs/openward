//! Hybrid logical clock (Kulkarni et al., 2014), packed in a `u64`: 48 bits
//! of milliseconds since the Unix epoch and 16 of counter. While the clocks
//! of the devices agree it orders writes like wall time; and a device never
//! gives a write a time before one it had already seen.

use std::fmt;

#[derive(Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Hlc(pub u64);

impl Hlc {
    pub fn at(ms: u64) -> Self {
        Self(ms << 16)
    }

    pub fn ms(self) -> u64 {
        self.0 >> 16
    }

    /// The next timestamp: the counter, carrying into the milliseconds.
    pub fn next(self) -> Self {
        Self(self.0 + 1)
    }
}

impl fmt::Debug for Hlc {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}.{}", self.ms(), self.0 & 0xffff)
    }
}

/// One device's clock.
#[derive(Clone, Debug)]
pub struct Clock {
    last: Hlc,
    /// How far ahead of this device's wall time another device's timestamp
    /// may be and still be followed.
    max_ahead_ms: u64,
}

impl Clock {
    pub fn new(max_ahead_ms: u64) -> Self {
        Self {
            last: Hlc::default(),
            max_ahead_ms,
        }
    }

    /// A timestamp for a local write: wall time, or just after the last one
    /// this clock gave or saw.
    pub fn tick(&mut self, now_ms: u64) -> Hlc {
        self.last = Hlc::at(now_ms).max(self.last.next());
        self.last
    }

    /// Learns another device's timestamp. One too far ahead of this
    /// device's wall time is not followed, or a single wrong clock would
    /// drag every device into its future for good; says whether it was.
    pub fn observe(&mut self, seen: Hlc, now_ms: u64) -> bool {
        if seen.ms() > now_ms.saturating_add(self.max_ahead_ms) {
            return false;
        }
        self.last = self.last.max(seen);
        true
    }

    /// Keeps the clock past a timestamp this device wrote itself.
    pub fn bump(&mut self, to: Hlc) {
        self.last = self.last.max(to);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_tick_is_wall_time_or_after_the_last() {
        let mut c = Clock::new(60_000);
        assert_eq!(c.tick(1000), Hlc::at(1000));
        // The wall clock went back: still after.
        assert_eq!(c.tick(900), Hlc::at(1000).next());
        assert!(c.observe(Hlc::at(5000), 1000 + 4000));
        assert_eq!(c.tick(1001), Hlc::at(5000).next());
    }

    #[test]
    fn a_clock_far_ahead_is_not_followed() {
        let mut c = Clock::new(60_000);
        c.tick(1000);
        assert!(!c.observe(Hlc::at(1000 + 61_000), 1000));
        assert_eq!(c.tick(1000), Hlc::at(1000).next());
    }

    #[test]
    fn the_counter_carries_into_the_milliseconds() {
        assert_eq!(Hlc(Hlc::at(7).0 | 0xffff).next(), Hlc::at(8));
    }
}
