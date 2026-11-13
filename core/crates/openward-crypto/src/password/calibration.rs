//! Bounded, measured calibration shared by all desktop platforms.
use super::{Error, KdfParams, MAX_MEMORY_KIB, MAX_WORK_KIB, MIN_MEMORY_KIB};
use std::time::{Duration, Instant};

const MIN: Duration = Duration::from_millis(500);
const TARGET: Duration = Duration::from_millis(750);
const MAX: Duration = Duration::from_secs(1);
const MAX_PROBES: usize = 12;

/// Run on a Rust worker at setup. Every proposed configuration is measured;
/// both ends of the 500–1000 ms target are enforced during the search. A machine
/// outside the resource policy (or unstable timing) returns its closest measured
/// result after at most 12 probes, without weakening the 64 MiB memory floor.
pub fn calibrate() -> Result<(KdfParams, Duration), Error> {
    calibrate_with(|params| {
        let start = Instant::now();
        drop(params.derive(b"openward calibration probe", &[0; 16])?);
        Ok(start.elapsed())
    })
}

fn calibrate_with(
    mut measure: impl FnMut(KdfParams) -> Result<Duration, Error>,
) -> Result<(KdfParams, Duration), Error> {
    let mut memory = MIN_MEMORY_KIB;
    let mut lower = 1;
    let mut upper = 16;
    let mut passes = 1;
    let mut best: Option<(KdfParams, Duration)> = None;
    for _ in 0..MAX_PROBES {
        let params = KdfParams::new(memory, passes)?;
        let elapsed = measure(params)?;
        let distance = |d: Duration| d.abs_diff(TARGET);
        if best.is_none_or(|(_, previous)| distance(elapsed) <= distance(previous)) {
            best = Some((params, elapsed));
        }
        if (MIN..=MAX).contains(&elapsed) {
            return Ok((params, elapsed));
        }
        // Bound each tier's pass search by measurements, including overshoots.
        // Strictly shrinking bounds also prevent oscillation under timing noise.
        if elapsed < MIN {
            lower = passes + 1;
        } else {
            upper = passes - 1;
        }
        if lower <= upper {
            passes = ((passes as u128 * TARGET.as_nanos()) / elapsed.as_nanos().max(1))
                .clamp(lower as u128, upper as u128) as u32;
        } else {
            // An overshoot exhausted the measured bounds on this tier. Keep the
            // closest observation instead of increasing its cost further.
            if elapsed > MAX || memory == MAX_MEMORY_KIB {
                break;
            }
            let next_memory = memory * 2;
            lower = 1;
            upper = 16.min(MAX_WORK_KIB / next_memory);
            // Preserve the target work estimate across a memory increase instead
            // of blindly doubling the cost with the old pass count.
            passes = ((passes as u128 * memory as u128 * TARGET.as_nanos())
                / (elapsed.as_nanos().max(1) * next_memory as u128))
                .clamp(lower as u128, upper as u128) as u32;
            memory = next_memory;
        }
    }
    Ok(best.expect("calibration always measures at least one valid configuration"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn windows_memory_increase_rescales_and_measures_the_new_pass_count() {
        let mut probes = Vec::new();
        let (params, elapsed) = calibrate_with(|p| {
            probes.push(p);
            Ok(Duration::from_micros(if p.memory_kib() == MIN_MEMORY_KIB {
                29_000 * p.passes() as u64
            } else {
                // Windows regression: 128 MiB / 16 passes took 1006 ms.
                62_878 * p.passes() as u64
            }))
        })
        .unwrap();
        assert_eq!(
            probes
                .iter()
                .map(|p| (p.memory_kib(), p.passes()))
                .collect::<Vec<_>>(),
            [(65536, 1), (65536, 16), (131072, 12)]
        );
        assert_eq!(params, *probes.last().unwrap());
        assert_eq!(elapsed, Duration::from_micros(62_878 * 12));
    }

    #[test]
    fn overshoot_is_reduced_and_measured_again_instead_of_returned() {
        let mut probes = Vec::new();
        let (params, elapsed) = calibrate_with(|p| {
            probes.push(p.passes());
            // A quick initial sample predicts too many passes.
            Ok(Duration::from_millis(if p.passes() == 1 {
                10
            } else {
                80 * p.passes() as u64
            }))
        })
        .unwrap();
        assert_eq!(probes, [1, 16, 9]);
        assert_eq!(params.passes(), 9);
        assert_eq!(elapsed, Duration::from_millis(720));
    }

    #[test]
    fn memory_tier_overshoot_also_reduces_passes() {
        let mut tier_probe = true;
        let (params, elapsed) = calibrate_with(|p| {
            let ms = if p.memory_kib() == MIN_MEMORY_KIB {
                28 * p.passes() as u64
            } else if tier_probe {
                tier_probe = false;
                1006
            } else {
                63 * p.passes() as u64
            };
            Ok(Duration::from_millis(ms))
        })
        .unwrap();
        assert_eq!(params.memory_kib(), 131072);
        assert!((MIN..=MAX).contains(&elapsed));
        assert!(params.passes() < 13);
    }

    #[test]
    fn target_edges_are_inclusive_and_slow_hardware_keeps_the_floor() {
        for millis in [500, 1000, 1200] {
            let mut calls = 0;
            let (params, elapsed) = calibrate_with(|_| {
                calls += 1;
                Ok(Duration::from_millis(millis))
            })
            .unwrap();
            assert_eq!(calls, 1);
            assert_eq!(params, KdfParams::new(MIN_MEMORY_KIB, 1).unwrap());
            assert_eq!(elapsed, Duration::from_millis(millis));
        }
    }

    #[test]
    fn fast_or_zero_resolution_clock_stays_within_memory_work_and_probe_limits() {
        for nanos in [0, 1, 1000, 2_000_000, 14_000_000, 40_000_000, 400_000_000] {
            let mut probes = Vec::new();
            let (params, elapsed) = calibrate_with(|p| {
                assert!((MIN_MEMORY_KIB..=MAX_MEMORY_KIB).contains(&p.memory_kib()));
                assert!(p.memory_kib() * p.passes() <= MAX_WORK_KIB);
                assert!(!probes.contains(&p));
                probes.push(p);
                Ok(Duration::from_nanos(
                    nanos * p.passes() as u64 * (p.memory_kib() / MIN_MEMORY_KIB) as u64,
                ))
            })
            .unwrap();
            assert!(!probes.is_empty() && probes.len() <= MAX_PROBES);
            assert!(probes.contains(&params));
            assert_eq!(
                elapsed,
                Duration::from_nanos(
                    nanos * params.passes() as u64 * (params.memory_kib() / MIN_MEMORY_KIB) as u64
                )
            );
            if nanos == 0 {
                assert_eq!(params, KdfParams::new(MAX_MEMORY_KIB, 8).unwrap());
            }
        }
    }

    #[test]
    fn probe_budget_exhaustion_returns_a_real_measurement() {
        let mut probes = Vec::new();
        let (params, elapsed) = calibrate_with(|p| {
            probes.push(p);
            Ok(Duration::from_millis(
                if p.memory_kib() == MIN_MEMORY_KIB || p.passes() < 11 {
                    499
                } else {
                    1001
                },
            ))
        })
        .unwrap();
        assert_eq!(probes.len(), MAX_PROBES);
        assert!(probes.contains(&params));
        assert_eq!(elapsed, Duration::from_millis(499));
    }

    #[test]
    fn timing_noise_is_bounded_and_measurement_errors_are_not_ignored() {
        let mut calls = 0;
        let (_, elapsed) = calibrate_with(|_| {
            calls += 1;
            Ok(Duration::from_millis(if calls % 2 == 0 {
                1400
            } else {
                400
            }))
        })
        .unwrap();
        assert!(calls <= MAX_PROBES);
        assert!(elapsed == Duration::from_millis(400) || elapsed == Duration::from_millis(1400));
        assert_eq!(calibrate_with(|_| Err(Error::Memory)), Err(Error::Memory));
        let mut first = true;
        assert_eq!(
            calibrate_with(|_| {
                if first {
                    first = false;
                    Ok(Duration::from_millis(100))
                } else {
                    Err(Error::Memory)
                }
            }),
            Err(Error::Memory)
        );
    }
}
